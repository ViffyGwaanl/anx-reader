import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  String? _currentSessionId;

  @override
  FutureOr<List<ChatMessage>> build() async {
    _currentSessionId = null;
    return List<ChatMessage>.empty();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    state = AsyncData(history);
  }

  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate, {
    int? regenerateFromUserIndex,
    bool replaceUserMessage = false,
  }) async* {
    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = widgetRef.read(aiHistoryProvider.notifier);
    final initialHistoryState = widgetRef
        .read(aiHistoryProvider)
        .maybeWhen(data: (value) => value, orElse: () => const []);
    AiChatHistoryEntry? entry;
    for (final item in initialHistoryState) {
      if (item.id == sessionId) {
        entry = item;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing =
        state.whenOrNull(data: (data) => data) ?? const <ChatMessage>[];

    List<ChatMessage> promptMessages;
    List<ChatMessage> visibleMessages;

    if (!isRegenerate && !replaceUserMessage) {
      promptMessages = [
        ...existing,
        ChatMessage.humanText(message),
      ];
      visibleMessages = promptMessages;
    } else {
      // Regenerate or edit+regenerate from a specific user message.
      var userIndex = regenerateFromUserIndex;
      if (userIndex == null) {
        for (var i = existing.length - 1; i >= 0; i--) {
          if (existing[i] is HumanChatMessage) {
            userIndex = i;
            break;
          }
        }
      }
      if (userIndex == null || userIndex < 0 || userIndex >= existing.length) {
        // Fallback to normal send.
        promptMessages = [
          ...existing,
          ChatMessage.humanText(message),
        ];
        visibleMessages = promptMessages;
      } else {
        final userMessage = existing[userIndex];
        if (userMessage is! HumanChatMessage) {
          promptMessages = [
            ...existing,
            ChatMessage.humanText(message),
          ];
          visibleMessages = promptMessages;
        } else {
          // Determine the end of this user turn (keep existing variants if any).
          var turnEnd = userIndex + 1;
          while (
              turnEnd < existing.length && existing[turnEnd] is AIChatMessage) {
            turnEnd++;
          }

          if (replaceUserMessage) {
            // Editing: replace the user content, drop old variants and everything after.
            visibleMessages = [
              ...existing.take(userIndex),
              ChatMessage.humanText(message),
            ];
            promptMessages = visibleMessages;
          } else {
            // Regenerate: keep existing variants for UI, but do NOT send them to the model.
            visibleMessages = existing.take(turnEnd).toList(growable: false);
            promptMessages =
                existing.take(userIndex + 1).toList(growable: false);
          }
        }
      }
    }

    state = AsyncData(visibleMessages);

    final updatedMessages = [
      ...visibleMessages,
      ChatMessage.ai(''),
    ];

    final draftEntry = (entry ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: entry?.createdAt ?? now,
              updatedAt: now,
              messages: List<ChatMessage>.from(updatedMessages),
              completed: false,
            ))
        .copyWith(
      messages: List<ChatMessage>.from(updatedMessages),
      updatedAt: now,
      completed: false,
      model: model,
    );

    // Do not block streaming on history persistence (can be slow/unavailable
    // in widget tests). Best-effort background write.
    state = AsyncData(updatedMessages);
    yield updatedMessages;
    historyNotifier.upsert(draftEntry).catchError((_) {});

    String assistantResponse = "";
    try {
      await for (final chunk in aiGenerateStream(
        promptMessages,
        regenerate: isRegenerate,
        useAgent: true,
        ref: widgetRef,
      )) {
        assistantResponse = chunk;

        final updatedMessagesWithResponse =
            List<ChatMessage>.from(updatedMessages);
        updatedMessagesWithResponse[updatedMessagesWithResponse.length - 1] =
            ChatMessage.ai(assistantResponse);

        yield updatedMessagesWithResponse;

        state = AsyncData(updatedMessagesWithResponse);
      }
      final completedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: true,
        model: model,
      );
      historyNotifier.upsert(completedEntry).catchError((_) {});
    } catch (_) {
      final failedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: false,
        model: model,
      );
      historyNotifier.upsert(failedEntry).catchError((_) {});
      rethrow;
    }
  }

  void clear() {
    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    _currentSessionId = entry.id;
    state = AsyncData(List<ChatMessage>.from(entry.messages));
  }

  String? get currentSessionId => _currentSessionId;

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}
