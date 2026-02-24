import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/models/ai_conversation_tree.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

@Riverpod(keepAlive: true)
class AiChatStreaming extends _$AiChatStreaming {
  @override
  bool build() => false;

  void setStreaming(bool value) {
    state = value;
  }
}

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  String? _currentSessionId;

  AiConversationTree _tree = AiConversationTree.empty();
  List<String> _activeNodeIds = const [];

  StreamSubscription<String>? _generationSub;
  AiChatHistoryEntry? _draftEntry;
  String? _draftAssistantNodeId;
  String? _draftHumanNodeId;

  @override
  FutureOr<List<ChatMessage>> build() async {
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];

    _generationSub?.cancel();
    _generationSub = null;
    _draftEntry = null;
    _draftAssistantNodeId = null;
    _draftHumanNodeId = null;

    return List<ChatMessage>.empty();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    _tree = AiConversationTree.fromLinearMessages(history);
    _rebuildFromTree();
  }

  bool get isStreaming => _generationSub != null;

  /// Start a streaming generation session.
  ///
  /// This runs inside the provider (not the UI widget), so minimizing/closing
  /// the chat panel will not interrupt generation.
  void startStreaming(
    String message,
    bool isRegenerate, {
    int? regenerateFromUserIndex,
    bool replaceUserMessage = false,
  }) {
    if (_generationSub != null) {
      return;
    }

    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final initialHistoryState = ref
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

    if (_tree.nodes.isEmpty) {
      _tree = AiConversationTree.empty();
    }

    // 1) Mutate tree.
    var parentId = _activeNodeIds.isEmpty ? _tree.rootId : _activeNodeIds.last;

    if (!isRegenerate && !replaceUserMessage) {
      _tree = _tree.appendChild(
        parentId: parentId,
        message: ChatMessage.humanText(message),
      );
      parentId = _tree.nodes[parentId]!.activeChildId!;
    } else {
      final userIndex = regenerateFromUserIndex ?? _findLastHumanIndex();
      if (userIndex != null &&
          userIndex >= 0 &&
          userIndex < _activeNodeIds.length) {
        final userNodeId = _activeNodeIds[userIndex];
        final userNode = _tree.nodes[userNodeId];
        if (userNode != null) {
          final parentOfUser = userNode.parentId ?? _tree.rootId;

          if (replaceUserMessage) {
            _tree = _tree.appendChild(
              parentId: parentOfUser,
              message: ChatMessage.humanText(message),
            );
            parentId = _tree.nodes[parentOfUser]!.activeChildId!;
          } else {
            parentId = userNodeId;
          }
        }
      }
    }

    _draftHumanNodeId = parentId;

    // 2) Assistant placeholder.
    _tree = _tree.appendChild(
      parentId: parentId,
      message: ChatMessage.ai(''),
    );
    _draftAssistantNodeId = _tree.nodes[parentId]!.activeChildId!;

    // 3) Update UI state + write draft entry.
    _rebuildFromTree();
    final updatedMessages = state.value ?? const <ChatMessage>[];

    _draftEntry = (entry ??
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
      conversationV2: _tree.toJson(),
    );

    historyNotifier.upsert(_draftEntry!).catchError((_) {});

    // 4) Start generation.
    final promptMessages = _buildPromptMessagesForAssistantParent(parentId);

    ref.read(aiChatStreamingProvider.notifier).setStreaming(true);

    final stream = aiGenerateStream(
      promptMessages,
      regenerate: isRegenerate,
      useAgent: true,
      ref: ref,
    );

    _generationSub = stream.listen(
      (chunk) {
        final assistantId = _draftAssistantNodeId;
        if (assistantId == null) {
          return;
        }
        _tree = _tree.updateNodeMessage(assistantId, ChatMessage.ai(chunk));
        _rebuildFromTree();
      },
      onError: (Object error, StackTrace stack) {
        _generationSub = null;
        _finalizeStreaming(completed: false);
      },
      onDone: () {
        _generationSub = null;
        _finalizeStreaming(completed: true);
      },
      cancelOnError: false,
    );
  }

  Future<void> cancelStreaming() async {
    if (_generationSub == null) {
      return;
    }

    cancelActiveAiRequest();

    try {
      await _generationSub?.cancel();
    } catch (_) {}

    _generationSub = null;
    _finalizeStreaming(completed: false);
  }

  void _finalizeStreaming({required bool completed}) {
    if (_generationSub != null) {
      return;
    }

    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final draftEntry = _draftEntry;
    if (draftEntry != null) {
      final finalEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? const <ChatMessage>[]),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: completed,
        conversationV2: _tree.toJson(),
      );
      historyNotifier.upsert(finalEntry).catchError((_) {});
    }

    _draftEntry = null;
    _draftAssistantNodeId = null;
    _draftHumanNodeId = null;
  }

  void clear() {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];

    _draftEntry = null;
    _draftAssistantNodeId = null;
    _draftHumanNodeId = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    _currentSessionId = entry.id;

    final rawTree = entry.conversationV2;
    if (rawTree != null) {
      _tree = AiConversationTree.fromJson(rawTree);
    } else {
      _tree = AiConversationTree.fromLinearMessages(entry.messages);
    }

    _rebuildFromTree();
  }

  String? get currentSessionId => _currentSessionId;

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  int? _findLastHumanIndex() {
    final messages = state.value;
    if (messages == null) return null;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  void _rebuildFromTree() {
    _activeNodeIds = _tree.activePathNodeIds();
    state = AsyncData(_tree.activePathMessages());
  }

  /// Build prompt messages up to the human message node [humanNodeId].
  List<ChatMessage> _buildPromptMessagesForAssistantParent(String humanNodeId) {
    // Walk from the human node back to root using parent pointers.
    final ids = <String>[];
    var currentId = humanNodeId;
    while (currentId != _tree.rootId) {
      ids.add(currentId);
      final node = _tree.nodes[currentId];
      final parentId = node?.parentId;
      if (parentId == null) break;
      currentId = parentId;
    }

    final orderedIds = ids.reversed.toList(growable: false);

    final messages = <ChatMessage>[];
    for (final id in orderedIds) {
      final node = _tree.nodes[id];
      final msg = node?.toChatMessage();
      if (msg != null) {
        messages.add(msg);
      }
    }

    return messages;
  }

  /// Switches the active variant for the message at [messageIndex] by [delta]
  /// among its siblings.
  void switchVariantAtMessageIndex(
    int messageIndex,
    int delta,
  ) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final node = _tree.nodes[nodeId];
    final parentId = node?.parentId;
    if (node == null || parentId == null) {
      return;
    }

    final siblings = _tree.siblingsOf(nodeId);
    final current = siblings.indexOf(nodeId);
    if (current < 0) return;

    final next = current + delta;
    if (next < 0 || next >= siblings.length) return;

    _tree = _tree.setActiveChild(parentId, siblings[next]);
    _rebuildFromTree();
  }

  void switchVariantAtMessageIndexAndPersist(
    int messageIndex,
    int delta,
    WidgetRef ref,
  ) {
    switchVariantAtMessageIndex(messageIndex, delta);
    persistCurrentConversation(ref);
  }

  int variantCountForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return 1;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final siblings = _tree.siblingsOf(nodeId);
    return siblings.isEmpty ? 1 : siblings.length;
  }

  int selectedVariantIndexForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return 0;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final siblings = _tree.siblingsOf(nodeId);
    if (siblings.isEmpty) return 0;
    final idx = siblings.indexOf(nodeId);
    return idx < 0 ? 0 : idx;
  }

  void persistCurrentConversation(WidgetRef ref) {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final existing = historyNotifier.findById(sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;

    final entry = (existing ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: now,
              updatedAt: now,
              messages: List<ChatMessage>.from(state.value ?? const []),
              completed: true,
            ))
        .copyWith(
      messages: List<ChatMessage>.from(state.value ?? const []),
      updatedAt: now,
      completed: true,
      model: model,
      conversationV2: _tree.toJson(),
    );

    historyNotifier.upsert(entry).catchError((_) {});
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}
