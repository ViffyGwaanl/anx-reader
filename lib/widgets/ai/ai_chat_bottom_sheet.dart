import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

/// Resizable AI chat bottom sheet.
///
/// Design goals:
/// - Allow minimizing the chat into a small bar so users can keep reading while
///   the assistant continues streaming.
/// - Persist the last sheet height.
/// - Avoid dismissing the sheet via drag (ReadingPage uses enableDrag=false).
class AiChatBottomSheet extends StatefulWidget {
  const AiChatBottomSheet({
    super.key,
    required this.aiChatKey,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.initialSizeOverride,
    this.rememberSize = true,
    this.onRequestClose,
  });

  final GlobalKey<AiChatStreamState> aiChatKey;
  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;

  /// Optional override for the initial sheet height (0-1).
  /// When set, it takes precedence over persisted size.
  final double? initialSizeOverride;

  /// Whether to persist sheet height while dragging.
  /// Note: minimized state is not persisted.
  final bool rememberSize;

  /// Close callback.
  /// - Modal sheet: pass `Navigator.pop`.
  /// - Persistent sheet: pass `PersistentBottomSheetController.close`.
  final VoidCallback? onRequestClose;

  @override
  State<AiChatBottomSheet> createState() => _AiChatBottomSheetState();
}

class _AiChatBottomSheetState extends State<AiChatBottomSheet> {
  static const double _minSize = 0.12;
  static const double _maxSize = 0.95;
  static const double _minimizedEpsilon = 0.02;

  final _sheetController = DraggableScrollableController();
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _scheduleSave(double size) {
    if (!widget.rememberSize) {
      return;
    }

    final clamped = size.clamp(_minSize, _maxSize).toDouble();
    // Don't persist the minimized bar state; reopening should start expanded.
    if (clamped <= _minSize + _minimizedEpsilon) {
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      Prefs().aiSheetInitialSize = clamped;
    });
  }

  Future<void> _minimize() async {
    try {
      await _sheetController.animateTo(
        _minSize,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // ignore (controller might not be attached yet)
    }
  }

  @override
  Widget build(BuildContext context) {
    var initial = (widget.initialSizeOverride ?? Prefs().aiSheetInitialSize)
        .clamp(_minSize, _maxSize)
        .toDouble();

    // If we ever persisted a minimized size, ignore it on open.
    if (initial <= _minSize + _minimizedEpsilon) {
      initial = _maxSize;
    }

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        _scheduleSave(n.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: initial,
        minChildSize: _minSize,
        maxChildSize: _maxSize,
        snap: true,
        snapSizes: const [
          _minSize,
          0.35,
          0.6,
          0.9,
          _maxSize,
        ],
        builder: (context, scrollController) {
          return Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            child: AiChatStream(
              key: widget.aiChatKey,
              initialMessage: widget.initialMessage,
              sendImmediate: widget.sendImmediate,
              quickPromptChips: widget.quickPromptChips,
              scrollController: scrollController,
              onRequestMinimize: _minimize,
              trailing: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: _minimize,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRequestClose ??
                      () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
