import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';

/// A persistent conversation tree that supports branching edits and per-turn
/// variants (Cherry-style).
///
/// Design:
/// - Nodes form a tree rooted at a sentinel [rootId].
/// - Each node has an ordered list of children.
/// - Each node stores an [activeChildId] pointer, which determines the active
///   conversation path. Switching variants updates the parent's activeChildId.
/// - The active path is derived by following [activeChildId] pointers from root.
@immutable
class AiConversationTree {
  const AiConversationTree({
    required this.rootId,
    required this.nodes,
  });

  final String rootId;
  final Map<String, AiConversationNode> nodes;

  factory AiConversationTree.empty() {
    const rootId = 'root';
    return AiConversationTree(
      rootId: rootId,
      nodes: {
        rootId: const AiConversationNode(
          id: rootId,
          parentId: null,
          children: <String>[],
          activeChildId: null,
          message: null,
          createdAt: 0,
          updatedAt: 0,
        ),
      },
    );
  }

  AiConversationNode get root => nodes[rootId]!;

  List<String> activePathNodeIds() {
    final result = <String>[];
    var currentId = rootId;
    while (true) {
      final node = nodes[currentId];
      if (node == null) break;
      final nextId = node.activeChildId;
      if (nextId == null) break;
      result.add(nextId);
      currentId = nextId;
    }
    return result;
  }

  List<ChatMessage> activePathMessages() {
    final ids = activePathNodeIds();
    return ids
        .map((id) => nodes[id])
        .whereType<AiConversationNode>()
        .map((n) => n.toChatMessage())
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  List<String> siblingsOf(String nodeId) {
    final node = nodes[nodeId];
    if (node == null) return const [];
    final parentId = node.parentId;
    if (parentId == null) return const [];
    final parent = nodes[parentId];
    return parent?.children ?? const [];
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 2,
      'rootId': rootId,
      'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  factory AiConversationTree.fromJson(Map<String, dynamic> json) {
    final rootId = json['rootId']?.toString() ?? 'root';
    final rawNodes = json['nodes'];
    final nodes = <String, AiConversationNode>{};

    if (rawNodes is Map) {
      for (final entry in rawNodes.entries) {
        final id = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          nodes[id] = AiConversationNode.fromJson(
            id,
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    }

    if (!nodes.containsKey(rootId)) {
      nodes[rootId] = AiConversationTree.empty().nodes[rootId]!;
    }

    return AiConversationTree(rootId: rootId, nodes: nodes);
  }

  /// Build a tree from a linear message list (migration from v1 history).
  ///
  /// Legacy history encodes assistant variants by appending multiple
  /// [AIChatMessage] consecutively after a single [HumanChatMessage]. This
  /// migration groups consecutive assistant messages under the latest human as
  /// siblings (variants), and uses the *last* assistant in the run as the active
  /// one.
  factory AiConversationTree.fromLinearMessages(List<ChatMessage> messages) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nodes =
        Map<String, AiConversationNode>.from(AiConversationTree.empty().nodes);

    // The last node on the active path (used to attach the next human message).
    var activeTailId = 'root';

    // The latest human node in the current turn (used to attach assistant variants).
    String? currentTurnHumanId;

    String newId() =>
        '${DateTime.now().microsecondsSinceEpoch}-${nodes.length}';

    void attachChild(String parentId, String childId) {
      final parent = nodes[parentId]!;
      nodes[parentId] = parent.copyWith(
        children: [...parent.children, childId],
        activeChildId: childId,
        updatedAt: now,
      );
    }

    for (final msg in messages) {
      if (msg is HumanChatMessage) {
        final id = newId();
        nodes[id] = AiConversationNode(
          id: id,
          parentId: activeTailId,
          children: const [],
          activeChildId: null,
          message: msg.toMap(),
          createdAt: now,
          updatedAt: now,
        );
        attachChild(activeTailId, id);
        activeTailId = id;
        currentTurnHumanId = id;
        continue;
      }

      if (msg is AIChatMessage) {
        final parentId = currentTurnHumanId ?? activeTailId;
        final id = newId();
        nodes[id] = AiConversationNode(
          id: id,
          parentId: parentId,
          children: const [],
          activeChildId: null,
          message: msg.toMap(),
          createdAt: now,
          updatedAt: now,
        );
        attachChild(parentId, id);

        // The active continuation after this turn should follow the latest
        // assistant variant.
        activeTailId = id;
        continue;
      }

      // Fallback: chain other message types.
      final id = newId();
      nodes[id] = AiConversationNode(
        id: id,
        parentId: activeTailId,
        children: const [],
        activeChildId: null,
        message: msg.toMap(),
        createdAt: now,
        updatedAt: now,
      );
      attachChild(activeTailId, id);
      activeTailId = id;
      currentTurnHumanId = null;
    }

    return AiConversationTree(rootId: 'root', nodes: nodes);
  }

  /// Returns a new tree with [parentId]'s active child switched to [childId].
  AiConversationTree setActiveChild(String parentId, String? childId) {
    final parent = nodes[parentId];
    if (parent == null) return this;
    if (childId != null && !parent.children.contains(childId)) {
      return this;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return copyWithNode(
      parentId,
      parent.copyWith(activeChildId: childId, updatedAt: now),
    );
  }

  AiConversationTree copyWithNode(String id, AiConversationNode node) {
    return AiConversationTree(
      rootId: rootId,
      nodes: {
        ...nodes,
        id: node,
      },
    );
  }

  /// Append a new child node under [parentId] and set it active.
  AiConversationTree appendChild({
    required String parentId,
    required ChatMessage message,
  }) {
    final parent = nodes[parentId];
    if (parent == null) return this;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${nodes.length}';
    final child = AiConversationNode(
      id: id,
      parentId: parentId,
      children: const [],
      activeChildId: null,
      message: message.toMap(),
      createdAt: now,
      updatedAt: now,
    );

    final updatedParent = parent.copyWith(
      children: [...parent.children, id],
      activeChildId: id,
      updatedAt: now,
    );

    return AiConversationTree(
      rootId: rootId,
      nodes: {
        ...nodes,
        parentId: updatedParent,
        id: child,
      },
    );
  }

  /// Update the message map for an existing node.
  AiConversationTree updateNodeMessage(String nodeId, ChatMessage message) {
    final node = nodes[nodeId];
    if (node == null) return this;
    final now = DateTime.now().millisecondsSinceEpoch;
    return copyWithNode(
      nodeId,
      node.copyWith(message: message.toMap(), updatedAt: now),
    );
  }
}

@immutable
class AiConversationNode {
  const AiConversationNode({
    required this.id,
    required this.parentId,
    required this.children,
    required this.activeChildId,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? parentId;
  final List<String> children;
  final String? activeChildId;

  /// A ChatMessage.toMap() map. Null only for the root sentinel node.
  final Map<String, dynamic>? message;

  final int createdAt;
  final int updatedAt;

  ChatMessage? toChatMessage() {
    final msg = message;
    if (msg == null) return null;
    return ChatMessage.fromMap(msg);
  }

  Map<String, dynamic> toJson() {
    return {
      'parentId': parentId,
      'children': children,
      'activeChildId': activeChildId,
      'message': message,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory AiConversationNode.fromJson(String id, Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = <String>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        children.add(item.toString());
      }
    }

    final rawMessage = json['message'];
    Map<String, dynamic>? message;
    if (rawMessage is Map) {
      message = rawMessage.map((k, v) => MapEntry(k.toString(), v));
    }

    return AiConversationNode(
      id: id,
      parentId: json['parentId']?.toString(),
      children: children,
      activeChildId: json['activeChildId']?.toString(),
      message: message,
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
    );
  }

  AiConversationNode copyWith({
    String? parentId,
    List<String>? children,
    String? activeChildId,
    Map<String, dynamic>? message,
    int? createdAt,
    int? updatedAt,
  }) {
    return AiConversationNode(
      id: id,
      parentId: parentId ?? this.parentId,
      children: children ?? this.children,
      activeChildId: activeChildId ?? this.activeChildId,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
