import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/inline_fulltext_translate_failure_reason.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/fulltext_translate_cache.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:crypto/crypto.dart';

String _sanitizeInlineFullTextTranslation(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Remove common code fences.
  s = s.replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\n'), '');
  s = s.replaceAll(RegExp(r'\n```$'), '');

  // Remove thinking blocks if any model leaks them.
  s = s.replaceAll(RegExp(r'<think>[\s\S]*?<\/think>', multiLine: true), '');

  // If the model returned HTML/XML-like tags, strip them.
  // Heuristic: only strip tags that look like markup (<p>, </div>, <!DOCTYPE ...>).
  final tagPattern = RegExp(r'<[a-zA-Z/!][^>]*>');
  final fullWidthTagPattern = RegExp(r'＜[a-zA-Z/!][^＞]*＞');
  final tagCount = tagPattern.allMatches(s).length;
  final fwTagCount = fullWidthTagPattern.allMatches(s).length;

  if (tagCount >= 1 || fwTagCount >= 1) {
    s = s.replaceAll(tagPattern, '');
    s = s.replaceAll(fullWidthTagPattern, '');
  }

  // Clean up extra whitespace introduced by stripping tags.
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return s.trim();
}

class FullTextTranslateRuntime {
  FullTextTranslateRuntime._();

  static final FullTextTranslateRuntime instance = FullTextTranslateRuntime._();

  // Default concurrency requirement confirmed by user.
  static const int defaultConcurrency = 4;

  final _Semaphore _semaphore = _Semaphore(defaultConcurrency);

  void _syncConcurrencyFromPrefs() {
    try {
      final desired = Prefs().inlineFullTextTranslateConcurrency;
      _semaphore.setMax(desired);
    } catch (_) {
      // Ignore prefs issues in tests / early boot.
    }
  }

  final Map<
      String,
      Future<
          ({
            String text,
            InlineFullTextTranslateFailureReason? failureReason
          })>> _inflight = {};

  String normalizeForCacheKey(String text) => _normalizeForCacheKey(text);

  String sanitize(String raw) => _sanitizeInlineFullTextTranslation(raw);

  String buildCacheKey({
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required String text,
  }) {
    final normalized = _normalizeForCacheKey(text);
    return sha1
        .convert(utf8.encode(
          'v1|book:$bookId|svc:${service.name}|from:${from.code}|to:${to.code}|$normalized',
        ))
        .toString();
  }

  Future<({String text, InlineFullTextTranslateFailureReason? failureReason})>
      translateWithMeta(
    TranslateService service,
    String text,
    LangListEnum from,
    LangListEnum to, {
    required int bookId,
    String? contextText,
    bool enableCache = true,
  }) async {
    _syncConcurrencyFromPrefs();

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return (
        text: '',
        failureReason: InlineFullTextTranslateFailureReason.unknown
      );
    }

    // Cache key MUST include bookId to enable per-book clear.
    final key = buildCacheKey(
      bookId: bookId,
      service: service,
      from: from,
      to: to,
      text: text,
    );

    if (enableCache) {
      final cached = await FullTextTranslateCache.get(bookId, key);
      if (cached != null && cached.isNotEmpty) {
        // Guard: old cache entries might contain original/echo content.
        if (!_looksUntranslated(text, cached)) {
          return (text: cached, failureReason: null);
        }
      }
    }

    final existing = _inflight[key];
    if (existing != null) {
      return await existing;
    }

    final future = _semaphore.withPermit(() async {
      // Extra retry layer for providers that return error strings (not exceptions).
      const maxAttempts = 3;

      InlineFullTextTranslateFailureReason classifyFailure({
        required bool looksUntranslated,
        required String lower,
        required String sanitized,
      }) {
        if (looksUntranslated) {
          return InlineFullTextTranslateFailureReason.untranslatedEcho;
        }
        if (lower.contains('authentication failed') ||
            lower.contains('unauthorized') ||
            lower.contains('invalid api key') ||
            lower.contains('401')) {
          return InlineFullTextTranslateFailureReason.auth;
        }
        if (lower.contains('rate limit') || lower.contains('429')) {
          return InlineFullTextTranslateFailureReason.rateLimit;
        }
        if (lower.contains('ai service not configured') ||
            lower.contains('ai 服务未配置')) {
          return InlineFullTextTranslateFailureReason.notConfigured;
        }
        if (lower.startsWith('error:') ||
            lower.contains('translate error') ||
            lower.contains('翻译错误')) {
          return InlineFullTextTranslateFailureReason.translateError;
        }
        if (sanitized.trim().isEmpty) {
          return InlineFullTextTranslateFailureReason.unknown;
        }
        return InlineFullTextTranslateFailureReason.unknown;
      }

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        String result;
        try {
          result = await service.provider.translateTextOnly(
            text,
            from,
            to,
            contextText: contextText,
          );
        } catch (_) {
          return (
            text: '',
            failureReason: InlineFullTextTranslateFailureReason.exception,
          );
        }

        final sanitized = sanitize(result);

        final lower = sanitized.trim().toLowerCase();
        final looksUntranslated = _looksUntranslated(text, sanitized);

        final looksBad = sanitized.trim().isEmpty ||
            looksUntranslated ||
            lower.startsWith('error:') ||
            lower.contains('translate error') ||
            lower.contains('翻译错误') ||
            lower.contains('authentication failed') ||
            lower.contains('rate limit') ||
            lower.contains('429') ||
            lower.contains('ai service not configured') ||
            lower.contains('ai 服务未配置');

        if (!looksBad) {
          if (enableCache) {
            await FullTextTranslateCache.set(bookId, key, sanitized);
          }
          return (text: sanitized, failureReason: null);
        }

        if (attempt < maxAttempts - 1) {
          // Backoff (rate limit needs longer pauses).
          final isRateLimit =
              lower.contains('rate limit') || lower.contains('429');
          final delay = isRateLimit
              ? Duration(milliseconds: 800 * (attempt + 1))
              : Duration(milliseconds: 200 * (attempt + 1));
          await Future<void>.delayed(delay);
          continue;
        }

        // Give up.
        return (
          text: '',
          failureReason: classifyFailure(
            looksUntranslated: looksUntranslated,
            lower: lower,
            sanitized: sanitized,
          ),
        );
      }

      return (
        text: '',
        failureReason: InlineFullTextTranslateFailureReason.unknown
      );
    });

    _inflight[key] = future;

    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<String> translate(
    TranslateService service,
    String text,
    LangListEnum from,
    LangListEnum to, {
    required int bookId,
    String? contextText,
    bool enableCache = true,
  }) async {
    final out = await translateWithMeta(
      service,
      text,
      from,
      to,
      bookId: bookId,
      contextText: contextText,
      enableCache: enableCache,
    );
    return out.text;
  }

  Future<void> clearBook(int bookId) async {
    await FullTextTranslateCache.clearBook(bookId);
  }

  bool _looksUntranslated(String original, String translated) {
    final o = _normalizeForCacheKey(original);
    final t = _normalizeForCacheKey(translated);

    if (o.isEmpty || t.isEmpty) return true;

    // Identity output for longer, letterful text is almost certainly "not translated".
    // (Allow identity for short fragments / numbers / punctuation.)
    if (t == o) {
      final hasLetter = RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(o);
      if (!hasLetter) return false;
      if (o.length < 20) return false;
      return true;
    }

    // Bilingual leakage: the model may echo the original paragraph and append a translation.
    // If translated contains a long prefix of the original, treat as failure so it can retry.
    if (o.length >= 80) {
      final prefixLen = o.length >= 120 ? 120 : 80;
      final prefix = o.substring(0, prefixLen);
      if (prefix.trim().isNotEmpty && t.contains(prefix)) {
        return true;
      }
    }

    return false;
  }

  String _normalizeForCacheKey(String text) {
    // Normalize in a way that keeps paragraph boundaries stable.
    // - Normalize CRLF
    // - Collapse spaces/tabs inside a line
    // - Collapse 3+ blank lines to 2
    final s = text.replaceAll('\r\n', '\n');
    final lines = s.split('\n').map((line) {
      return line.replaceAll(RegExp(r'[\t ]+'), ' ').trimRight();
    }).toList(growable: false);

    var normalized = lines.join('\n').trim();
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized;
  }
}

class _Semaphore {
  _Semaphore(this._max);

  int _max;
  int _current = 0;
  final Queue<Completer<void>> _queue = Queue();

  void setMax(int max) {
    final next = max.clamp(1, 32);
    if (next == _max) return;
    _max = next;

    // If we increased capacity, release queued waiters.
    while (_queue.isNotEmpty && _current < _max) {
      final c = _queue.removeFirst();
      if (!c.isCompleted) c.complete();
      // _current will be incremented when that waiter resumes.
    }
  }

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future.then((_) {
      _current++;
    });
  }

  void _release() {
    _current--;
    if (_current < 0) _current = 0;
    if (_queue.isNotEmpty && _current < _max) {
      final next = _queue.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }
}
