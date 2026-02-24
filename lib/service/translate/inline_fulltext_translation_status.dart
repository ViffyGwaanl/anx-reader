import 'dart:math';

import 'package:anx_reader/enums/inline_fulltext_translate_failure_reason.dart';
import 'package:anx_reader/models/inline_fulltext_translation_progress.dart';
import 'package:flutter/foundation.dart';

/// A lightweight global bus for reporting *inline full-text translation* status.
///
/// Motivation:
/// - Translation tasks run async while reading ("后台翻译").
/// - We want a single observable place for Settings pages to show live status.
///
/// Note:
/// - This is intentionally *non-persistent* session state.
/// - It is updated by the reading WebView side (EpubPlayer).
class InlineFullTextTranslationStatusBus {
  InlineFullTextTranslationStatusBus._();

  static final InlineFullTextTranslationStatusBus instance =
      InlineFullTextTranslationStatusBus._();

  final ValueNotifier<InlineFullTextTranslationProgress> progress =
      ValueNotifier(InlineFullTextTranslationProgress.idle());

  final ValueNotifier<Map<InlineFullTextTranslateFailureReason, int>>
      failureReasons = ValueNotifier(const {});

  void reset() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = progress.value;
    progress.value = InlineFullTextTranslationProgress.idle().copyWith(
      generation: prev.generation + 1,
      updatedAtMs: now,
    );
    failureReasons.value = const {};
  }

  void update({
    required int total,
    required int inflight,
    required int done,
    required int failed,
    Map<InlineFullTextTranslateFailureReason, int>? failureReasons,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = progress.value;

    final pending = max(0, total - inflight - done - failed);

    progress.value = prev.copyWith(
      active: total > 0 || inflight > 0,
      total: total,
      pending: pending,
      inflight: inflight,
      done: done,
      failed: failed,
      generation: prev.generation + 1,
      updatedAtMs: now,
    );

    if (failureReasons != null) {
      this.failureReasons.value = Map.unmodifiable(failureReasons);
    }
  }

  void reportManualRetry({
    required int started,
    required int candidates,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = progress.value;

    progress.value = prev.copyWith(
      lastRetryAtMs: now,
      lastRetryStarted: started,
      lastRetryCandidates: candidates,
      generation: prev.generation + 1,
      updatedAtMs: now,
    );
  }
}
