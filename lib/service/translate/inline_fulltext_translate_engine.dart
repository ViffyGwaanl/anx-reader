import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/models/inline_fulltext_translation_progress.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/translate/fulltext_translate_cache.dart';
import 'package:anx_reader/service/translate/fulltext_translate_runtime.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class InlineFullTextTranslateBlock {
  const InlineFullTextTranslateBlock({required this.id, required this.text});

  final String id;
  final String text;

  static List<InlineFullTextTranslateBlock> parseList(Object? raw) {
    if (raw is! List) return const [];
    final out = <InlineFullTextTranslateBlock>[];
    for (final item in raw) {
      if (item is Map) {
        final id = item['id']?.toString() ?? '';
        final text = item['text']?.toString() ?? '';
        if (id.isEmpty || text.trim().isEmpty) continue;
        out.add(InlineFullTextTranslateBlock(id: id, text: text));
      }
    }
    return out;
  }
}

class InlineFullTextTranslateEngine {
  InlineFullTextTranslateEngine({
    required this.progress,
    required this.maxConcurrency,
  }) : _semaphore = _Semaphore(maxConcurrency);

  final ValueNotifier<InlineFullTextTranslationProgress> progress;
  final int maxConcurrency;

  final _Semaphore _semaphore;

  bool _disposed = false;

  // Active viewport ids (current + next viewport)
  Set<String> _activeIds = <String>{};

  // State (session-level)
  final Set<String> _doneIds = <String>{};
  final Set<String> _failedIds = <String>{};
  final Map<String, Future<void>> _inflightById = <String, Future<void>>{};

  // Attempt counts for retry
  final Map<String, int> _attempts = <String, int>{};

  int _progressGeneration = 0;

  Future<void> submit({
    required InAppWebViewController webViewController,
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required List<InlineFullTextTranslateBlock> blocks,
  }) async {
    if (_disposed) return;
    if (blocks.isEmpty) {
      _activeIds = <String>{};
      _recomputeProgress();
      return;
    }

    // Deduplicate by id.
    final byId = <String, InlineFullTextTranslateBlock>{};
    for (final b in blocks) {
      if (b.id.isEmpty) continue;
      if (b.text.trim().isEmpty) continue;
      byId[b.id] = b;
    }

    _activeIds = byId.keys.toSet();
    _progressGeneration++;

    // First: apply cached translations immediately (zero latency).
    await _applyCached(
      webViewController: webViewController,
      bookId: bookId,
      service: service,
      from: from,
      to: to,
      blocks: byId.values.toList(growable: false),
    );

    _recomputeProgress();

    // Schedule translation for remaining blocks.
    if (service == TranslateService.aiFullText) {
      _scheduleAiBatches(
        webViewController: webViewController,
        bookId: bookId,
        from: from,
        to: to,
        blocksById: byId,
      );
    } else {
      _schedulePerBlock(
        webViewController: webViewController,
        bookId: bookId,
        service: service,
        from: from,
        to: to,
        blocksById: byId,
      );
    }
  }

  Future<void> _applyCached({
    required InAppWebViewController webViewController,
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required List<InlineFullTextTranslateBlock> blocks,
  }) async {
    for (final b in blocks) {
      if (_disposed) return;
      if (_doneIds.contains(b.id)) continue;

      final key = FullTextTranslateRuntime.instance.buildCacheKey(
        bookId: bookId,
        service: service,
        from: from,
        to: to,
        text: b.text,
      );

      final cached = await FullTextTranslateCache.get(bookId, key);
      if (cached != null && cached.trim().isNotEmpty) {
        await _applyToWeb(
          webViewController: webViewController,
          id: b.id,
          translated: cached,
        );
        _doneIds.add(b.id);
        _failedIds.remove(b.id);
      }
    }
  }

  void _schedulePerBlock({
    required InAppWebViewController webViewController,
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required Map<String, InlineFullTextTranslateBlock> blocksById,
  }) {
    for (final entry in blocksById.entries) {
      final id = entry.key;
      final block = entry.value;

      if (_disposed) return;
      if (_doneIds.contains(id)) continue;
      if (_inflightById.containsKey(id)) continue;

      final future = _semaphore.withPermit(() async {
        try {
          final translated = await FullTextTranslateRuntime.instance.translate(
            service,
            block.text,
            from,
            to,
            bookId: bookId,
          );

          final t = translated.trim();
          final isError = t.toLowerCase().startsWith('error:') ||
              t.contains('AI service not configured') ||
              t.contains('AI 服务未配置') ||
              t.contains('Authentication failed');

          if (!isError && t.isNotEmpty && !_disposed) {
            await _applyToWeb(
              webViewController: webViewController,
              id: id,
              translated: translated,
            );
            _doneIds.add(id);
            _failedIds.remove(id);
          } else {
            _failedIds.add(id);
          }
        } catch (_) {
          _failedIds.add(id);
        } finally {
          _inflightById.remove(id);
          _recomputeProgress();
        }
      });

      _inflightById[id] = future;
      _recomputeProgress();
    }
  }

  void _scheduleAiBatches({
    required InAppWebViewController webViewController,
    required int bookId,
    required LangListEnum from,
    required LangListEnum to,
    required Map<String, InlineFullTextTranslateBlock> blocksById,
  }) {
    // Build pending list.
    final pending = <InlineFullTextTranslateBlock>[];
    for (final b in blocksById.values) {
      if (_doneIds.contains(b.id)) continue;
      if (_inflightById.containsKey(b.id)) continue;
      pending.add(b);
    }

    if (pending.isEmpty) {
      _recomputeProgress();
      return;
    }

    final batches = _groupBatches(pending);

    for (final batch in batches) {
      if (_disposed) return;

      // Mark inflight.
      for (final b in batch) {
        // We use a placeholder future; it will be replaced below.
        _inflightById[b.id] = Future.value();
        _failedIds.remove(b.id);
      }
      _recomputeProgress();

      // ignore: discarded_futures
      _semaphore.withPermit(() async {
        final ids = batch.map((e) => e.id).toSet();
        try {
          final resultMap = await _translateBatchAi(
            blocks: batch,
            to: to,
            from: from,
          );

          // Apply translations
          for (final b in batch) {
            final translated = resultMap[b.id];
            if (translated != null && translated.trim().isNotEmpty) {
              // Cache (use aiFullText as service)
              final key = FullTextTranslateRuntime.instance.buildCacheKey(
                bookId: bookId,
                service: TranslateService.aiFullText,
                from: from,
                to: to,
                text: b.text,
              );
              await FullTextTranslateCache.set(bookId, key, translated);

              await _applyToWeb(
                webViewController: webViewController,
                id: b.id,
                translated: translated,
              );
              _doneIds.add(b.id);
              _failedIds.remove(b.id);
            } else {
              _failedIds.add(b.id);
            }
          }

          // Fallback: for missing ids, try per-block once.
          final missing = batch
              .where((b) => !_doneIds.contains(b.id))
              .toList(growable: false);
          for (final b in missing) {
            final attempt = (_attempts[b.id] ?? 0) + 1;
            _attempts[b.id] = attempt;
            if (attempt > 1) continue;

            try {
              final translated = await FullTextTranslateRuntime.instance.translate(
                TranslateService.aiFullText,
                b.text,
                from,
                to,
                bookId: bookId,
              );
              if (translated.trim().isNotEmpty) {
                await _applyToWeb(
                  webViewController: webViewController,
                  id: b.id,
                  translated: translated,
                );
                _doneIds.add(b.id);
                _failedIds.remove(b.id);
              }
            } catch (_) {}
          }
        } catch (_) {
          // Batch failed (most likely JSON non-compliance). Mark failed, then
          // fallback to per-block translation (best-effort) so the feature still works.
          for (final b in batch) {
            _failedIds.add(b.id);
          }

          // Remove inflight placeholders before scheduling fallback.
          for (final id in ids) {
            _inflightById.remove(id);
          }
          _recomputeProgress();

          // Fallback: per-block using translateFulltext prompt.
          _schedulePerBlock(
            webViewController: webViewController,
            bookId: bookId,
            service: TranslateService.aiFullText,
            from: from,
            to: to,
            blocksById: {
              for (final b in batch) b.id: b,
            },
          );
        } finally {
          // Ensure placeholders removed (if not already removed by fallback path).
          for (final id in ids) {
            _inflightById.remove(id);
          }
          _recomputeProgress();
        }
      });
    }
  }

  List<List<InlineFullTextTranslateBlock>> _groupBatches(
    List<InlineFullTextTranslateBlock> blocks,
  ) {
    // Heuristic batch sizing for current+next viewport.
    // Keep batches small to improve JSON compliance.
    const maxBatchChars = 4000;
    const maxBatchCount = 12;

    final batches = <List<InlineFullTextTranslateBlock>>[];
    var current = <InlineFullTextTranslateBlock>[];
    var chars = 0;

    for (final b in blocks) {
      final len = b.text.length;
      final wouldExceed =
          (current.length + 1 > maxBatchCount) || (chars + len > maxBatchChars);

      if (current.isNotEmpty && wouldExceed) {
        batches.add(current);
        current = <InlineFullTextTranslateBlock>[];
        chars = 0;
      }

      current.add(b);
      chars += len;
    }

    if (current.isNotEmpty) {
      batches.add(current);
    }

    return batches;
  }

  String? _extractJsonArray(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Strip common code fences.
    s = s.replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\n'), '');
    s = s.replaceAll(RegExp(r'\n```$'), '');

    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return s.substring(start, end + 1);
    }
    return null;
  }

  Future<Map<String, String>> _translateBatchAi({
    required List<InlineFullTextTranslateBlock> blocks,
    required LangListEnum to,
    required LangListEnum from,
  }) async {
    final input = blocks
        .map((b) => {
              'id': b.id,
              'text': b.text,
            })
        .toList(growable: false);

    final blocksJson = jsonEncode(input);

    final payload = generatePromptTranslateFulltextBlocksJson(
      blocksJson,
      to.nativeName,
      from.nativeName,
    );

    final messages = payload.buildMessages();

    String? last;
    await for (final chunk in aiGenerateStream(messages, regenerate: false)) {
      last = chunk;
    }

    final raw = (last ?? '').trim();
    if (raw.isEmpty) {
      throw const FormatException('Empty AI response');
    }

    if (raw.toLowerCase().startsWith('error:')) {
      throw FormatException('AI error response: ${raw.substring(0, raw.length.clamp(0, 80))}');
    }

    Object decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      final extracted = _extractJsonArray(raw);
      if (extracted == null) {
        throw const FormatException('Invalid JSON (no array found)');
      }
      decoded = jsonDecode(extracted);
    }

    if (decoded is! List) {
      throw const FormatException('Invalid JSON (not an array)');
    }

    final out = <String, String>{};
    for (final item in decoded) {
      if (item is Map) {
        final id = item['id']?.toString() ?? '';
        final t = item['translation']?.toString() ?? '';
        if (id.isEmpty) continue;
        final sanitized = FullTextTranslateRuntime.instance.sanitize(t);
        if (sanitized.trim().isEmpty) continue;
        out[id] = sanitized;
      }
    }

    if (out.isEmpty) {
      throw const FormatException('JSON parsed but no usable items');
    }

    return out;
  }

  Future<void> _applyToWeb({
    required InAppWebViewController webViewController,
    required String id,
    required String translated,
  }) async {
    final js = '''
try {
  if (typeof reader !== 'undefined' && reader.view && reader.view.applyFullTextTranslation) {
    reader.view.applyFullTextTranslation(${_jsString(id)}, ${_jsString(translated)});
  }
} catch (e) {}
''';
    await webViewController.evaluateJavascript(source: js);
  }

  void _recomputeProgress() {
    if (_disposed) return;

    final ids = _activeIds;

    final total = ids.length;
    var done = 0;
    var inflight = 0;
    var failed = 0;

    for (final id in ids) {
      if (_doneIds.contains(id)) {
        done++;
      } else if (_inflightById.containsKey(id)) {
        inflight++;
      } else if (_failedIds.contains(id)) {
        failed++;
      }
    }

    final pending = (total - done - inflight - failed).clamp(0, 1 << 30);
    final active = inflight > 0 || pending > 0;

    progress.value = InlineFullTextTranslationProgress(
      active: active,
      total: total,
      pending: pending,
      inflight: inflight,
      done: done,
      failed: failed,
      generation: _progressGeneration,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {
    _disposed = true;
    _activeIds = <String>{};
    _inflightById.clear();
  }
}

String _jsString(String s) {
  // Minimal JS string literal escaping.
  final escaped = s
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll('"', r'\\"')
      .replaceAll("'", r"\\'");
  return '"$escaped"';
}

class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _queue = Queue();

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
