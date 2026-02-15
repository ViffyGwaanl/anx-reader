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
class AiChat extends _$AiChat {
  String? _currentSessionId;

  AiConversationTree _tree = AiConversationTree.empty();
  List<String> _activeNodeIds = const [];

  @override
  FutureOr<List<ChatMessage>> build() async {
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];
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
    _tree = AiConversationTree.fromLinearMessages(history);
    _rebuildFromTree();
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

    // Ensure tree is initialized.
    if (_tree.nodes.isEmpty) {
      _tree = AiConversationTree.empty();
    }

    // 1) Mutate tree: create a new branch/message if needed.
    String parentId =
        _activeNodeIds.isEmpty ? _tree.rootId : _activeNodeIds.last;

    if (!isRegenerate && !replaceUserMessage) {
      // New message at the end.
      _tree = _tree.appendChild(
        parentId: parentId,
        message: ChatMessage.humanText(message),
      );
      parentId = _tree.nodes[parentId]!.activeChildId!;
    } else {
      // Regenerate/edit from a specific human message.
      final userIndex = regenerateFromUserIndex ?? _findLastHumanIndex();
      if (userIndex != null &&
          userIndex >= 0 &&
          userIndex < _activeNodeIds.length) {
        final userNodeId = _activeNodeIds[userIndex];
        final userNode = _tree.nodes[userNodeId];
        if (userNode != null) {
          final parentOfUser = userNode.parentId ?? _tree.rootId;

          if (replaceUserMessage) {
            // Edit creates a new *sibling* human node (branch), preserving the old one.
            _tree = _tree.appendChild(
              parentId: parentOfUser,
              message: ChatMessage.humanText(message),
            );
            parentId = _tree.nodes[parentOfUser]!.activeChildId!;
          } else {
            // Regenerate creates a new assistant variant under the existing human node.
            parentId = userNodeId;
          }
        }
      }
    }

    // 2) Create assistant placeholder under [parentId] (either new human or existing human).
    _tree = _tree.appendChild(
      parentId: parentId,
      message: ChatMessage.ai(''),
    );
    final assistantNodeId = _tree.nodes[parentId]!.activeChildId!;

    // 3) Rebuild active view and write draft.
    _rebuildFromTree();
    final updatedMessages = state.value ?? const <ChatMessage>[];
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
      conversationV2: _tree.toJson(),
    );

    yield updatedMessages;
    historyNotifier.upsert(draftEntry).catchError((_) {});

    // 4) Build prompt messages: use the active path up to the parentId (human) + placeholder? We send up to the human.
    final promptMessages = _buildPromptMessagesForAssistantParent(parentId);

    try {
      await for (final chunk in aiGenerateStream(
        promptMessages,
        regenerate: isRegenerate,
        useAgent: true,
        ref: widgetRef,
      )) {
        _tree = _tree.updateNodeMessage(assistantNodeId, ChatMessage.ai(chunk));
        _rebuildFromTree();
        yield state.value ?? const <ChatMessage>[];
      }

      final completedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: true,
        model: model,
        conversationV2: _tree.toJson(),
      );
      historyNotifier.upsert(completedEntry).catchError((_) {});
    } catch (_) {
      final failedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: false,
        model: model,
        conversationV2: _tree.toJson(),
      );
      historyNotifier.upsert(failedEntry).catchError((_) {});
      rethrow;
    }
  }

  void clear() {
    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
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
