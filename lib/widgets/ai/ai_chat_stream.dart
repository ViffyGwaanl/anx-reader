import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/enums/ai_thinking_mode.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';

import 'package:anx_reader/models/ai_quick_prompt_chip.dart';

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream({
    super.key,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.trailing,
  });

  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  final TextEditingController inputController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Stream<List<ChatMessage>>? _messageStream;
  StreamController<List<ChatMessage>>? _messageController;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _isStreaming = false;

  // For each user turn, the assistant may have multiple generated variants.
  // We keep a lightweight UI-only selection index per turn.
  final Map<int, int> _selectedVariantByUserIndex = {};

  late final List<AiServiceOption> _builtInOptions;
  late final Map<String, AiServiceOption> _builtInById;
  late List<AiProviderMeta> _providers;
  late String _selectedProviderId;

  late List<String> _suggestedPrompts;
  late List<String> _starterPrompts;

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
    return [
      {
        'label': L10n.of(context).aiQuickPromptExplain,
        'prompt': L10n.of(context).aiQuickPromptExplainText,
      },
      {
        'label': L10n.of(context).aiQuickPromptOpinion,
        'prompt': L10n.of(context).aiQuickPromptOpinionText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSummary,
        'prompt': L10n.of(context).aiQuickPromptSummaryText,
      },
      {
        'label': L10n.of(context).aiQuickPromptAnalyze,
        'prompt': L10n.of(context).aiQuickPromptAnalyzeText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSuggest,
        'prompt': L10n.of(context).aiQuickPromptSuggestText,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _starterPrompts = [
      L10n.of(navigatorKey.currentContext!).quickPrompt1,
      L10n.of(navigatorKey.currentContext!).quickPrompt2,
      L10n.of(navigatorKey.currentContext!).quickPrompt3,
      L10n.of(navigatorKey.currentContext!).quickPrompt4,
      L10n.of(navigatorKey.currentContext!).quickPrompt5,
      L10n.of(navigatorKey.currentContext!).quickPrompt6,
      L10n.of(navigatorKey.currentContext!).quickPrompt7,
      L10n.of(navigatorKey.currentContext!).quickPrompt8,
      L10n.of(navigatorKey.currentContext!).quickPrompt9,
      L10n.of(navigatorKey.currentContext!).quickPrompt10,
      L10n.of(navigatorKey.currentContext!).quickPrompt11,
      L10n.of(navigatorKey.currentContext!).quickPrompt12,
    ];
    _builtInOptions = buildDefaultAiServices();
    _builtInById = {
      for (final option in _builtInOptions) option.identifier: option,
    };

    _ensureProvidersInitialized();
    _providers = Prefs().aiProvidersV1;

    _selectedProviderId = Prefs().selectedAiService;
    if (!_isProviderSelectable(_selectedProviderId)) {
      _selectedProviderId = _fallbackProviderId(_providers);
      Prefs().selectedAiService = _selectedProviderId;
    }
    inputController.text = widget.initialMessage ?? '';
    _suggestedPrompts = _pickSuggestedPrompts();
    if (widget.sendImmediate) {
      _sendMessage();
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    inputController.dispose();
    _messageSubscription?.cancel();
    _messageController?.close();
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureProvidersInitialized() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final builtIns = _builtInOptions.map((option) {
      final type = switch (option.identifier) {
        'claude' => AiProviderType.anthropic,
        'gemini' => AiProviderType.gemini,
        _ => AiProviderType.openaiCompatible,
      };

      return AiProviderMeta(
        id: option.identifier,
        name: option.title,
        type: type,
        enabled: true,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        logoKey: option.logo,
      );
    }).toList(growable: false);

    Prefs().ensureAiProvidersV1Initialized(builtIns: builtIns);
  }

  AiProviderMeta? _providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _isProviderSelectable(String id) {
    final p = _providerById(id);
    return p != null && p.enabled;
  }

  String _fallbackProviderId(List<AiProviderMeta> providers) {
    for (final p in providers) {
      if (p.id == 'openai' && p.enabled) return p.id;
    }
    for (final p in providers) {
      if (p.enabled) return p.id;
    }
    return 'openai';
  }

  AiProviderMeta get _currentProvider {
    return _providerById(_selectedProviderId) ??
        (_providers.isNotEmpty
            ? _providers.first
            : AiProviderMeta(
                id: 'openai',
                name: 'OpenAI',
                type: AiProviderType.openaiCompatible,
                enabled: true,
                isBuiltIn: true,
                createdAt: 0,
                updatedAt: 0,
              ));
  }

  AiServiceOption? _builtInOptionForProvider(AiProviderMeta meta) {
    final exact = _builtInById[meta.id];
    if (exact != null) return exact;

    // Custom providers: fall back to the built-in logo/model per type.
    switch (meta.type) {
      case AiProviderType.anthropic:
        return _builtInById['claude'];
      case AiProviderType.gemini:
        return _builtInById['gemini'];
      case AiProviderType.openaiCompatible:
        return _builtInById['openai'];
    }
  }

  String _providerLogoKey(AiProviderMeta meta) {
    return meta.logoKey ?? _builtInOptionForProvider(meta)?.logo ?? '';
  }

  String _modelLabel(String providerId) {
    final stored = Prefs().getAiConfig(providerId);
    final model = stored['model']?.trim();
    if (model != null && model.isNotEmpty) {
      return model;
    }

    final meta = _providerById(providerId);
    final builtIn = meta == null
        ? _builtInById[providerId]
        : _builtInOptionForProvider(meta);

    return builtIn?.defaultModel ?? '';
  }

  void _onProviderSelected(String providerId) {
    if (_isStreaming || providerId == _selectedProviderId) return;
    if (!_isProviderSelectable(providerId)) return;

    Prefs().selectedAiService = providerId;
    setState(() {
      _selectedProviderId = providerId;
    });
  }

  AiThinkingMode _thinkingModeForProvider(String providerId) {
    final existing = Prefs().getAiConfig(providerId);
    return aiThinkingModeFromString(existing['thinking_mode'] ?? 'off');
  }

  bool _includeThoughtsForProvider(AiProviderMeta provider) {
    if (provider.type != AiProviderType.gemini) {
      return false;
    }
    final existing = Prefs().getAiConfig(provider.id);
    final raw = (existing['include_thoughts'] ?? 'true').trim().toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  String _thinkingModeLabel(AiThinkingMode mode, L10n l10n) {
    switch (mode) {
      case AiThinkingMode.off:
        return l10n.aiThinkingOff;
      case AiThinkingMode.auto:
        return l10n.aiThinkingAuto;
      case AiThinkingMode.minimal:
        return l10n.aiThinkingMinimal;
      case AiThinkingMode.low:
        return l10n.aiThinkingLow;
      case AiThinkingMode.medium:
        return l10n.aiThinkingMedium;
      case AiThinkingMode.high:
        return l10n.aiThinkingHigh;
    }
  }

  List<AiThinkingMode> _supportedThinkingModes(AiProviderMeta provider) {
    final stored = Prefs().getAiConfig(provider.id);
    final model = (stored['model'] ?? '').trim().toLowerCase();

    switch (provider.type) {
      case AiProviderType.openaiCompatible:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.anthropic:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.gemini:
        // Best-effort gating based on Gemini official doc.
        if (model.contains('gemini-3-pro')) {
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.high,
          ];
        }
        if (model.contains('gemini-2.5-pro')) {
          // Doc says: cannot disable thinking.
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.medium,
            AiThinkingMode.high,
          ];
        }
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
    }
  }

  IconData _thinkingIcon(AiThinkingMode mode) {
    switch (mode) {
      case AiThinkingMode.off:
        return Icons.lightbulb_outline;
      case AiThinkingMode.auto:
        return Icons.auto_awesome;
      case AiThinkingMode.minimal:
        return Icons.lightbulb_outline;
      case AiThinkingMode.low:
        return Icons.lightbulb_outline;
      case AiThinkingMode.medium:
        return Icons.lightbulb;
      case AiThinkingMode.high:
        return Icons.lightbulb;
    }
  }

  Future<void> _editThinkingMode() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;
    final supported = _supportedThinkingModes(provider);

    final current = _thinkingModeForProvider(provider.id);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              ListTile(
                title: Text(l10n.aiThinkingTitle),
                subtitle: Text(provider.name),
              ),
              if (provider.type == AiProviderType.gemini)
                SwitchListTile.adaptive(
                  title:
                      Text(l10n.settingsAiProviderCenterIncludeThoughtsTitle),
                  subtitle:
                      Text(l10n.settingsAiProviderCenterIncludeThoughtsDesc),
                  value: _includeThoughtsForProvider(provider),
                  onChanged: (v) {
                    final next = Map<String, String>.from(
                      Prefs().getAiConfig(provider.id),
                    );
                    next['include_thoughts'] = v ? 'true' : 'false';
                    Prefs().saveAiConfig(provider.id, next);
                    setState(() {});
                  },
                ),
              for (final mode in AiThinkingMode.values)
                RadioListTile<AiThinkingMode>(
                  value: mode,
                  groupValue: current,
                  title: Text(_thinkingModeLabel(mode, l10n)),
                  secondary: Icon(_thinkingIcon(mode)),
                  onChanged: supported.contains(mode)
                      ? (v) {
                          if (v == null) return;
                          final next = Map<String, String>.from(
                            Prefs().getAiConfig(provider.id),
                          );
                          next['thinking_mode'] = aiThinkingModeToString(v);
                          Prefs().saveAiConfig(provider.id, next);
                          setState(() {});
                          Navigator.of(context).pop();
                        }
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editCurrentModel() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;

    final existing = Prefs().getAiConfig(provider.id);
    final controller = TextEditingController(
      text: (existing['model'] ?? '').trim(),
    );

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          final cached = Prefs().getAiModelsCacheV1(provider.id)?.models ??
              const <String>[];

          return AlertDialog(
            title: Text(l10n.aiChatEditModelTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cached.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: cached.contains(controller.text.trim())
                        ? controller.text.trim()
                        : null,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                    items: cached
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      controller.text = v;
                    },
                  )
                else
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.commonSave),
              ),
            ],
          );
        },
      );

      if (ok != true || !mounted) return;

      final nextModel = controller.text.trim();
      final next = Map<String, String>.from(existing);
      if (nextModel.isEmpty) {
        next.remove('model');
      } else {
        next['model'] = nextModel;
      }

      Prefs().saveAiConfig(provider.id, next);
      setState(() {});
    } finally {
      controller.dispose();
    }
  }

  List<String> _pickSuggestedPrompts() {
    final prompts = List<String>.from(_starterPrompts)..shuffle();
    return prompts.take(3).toList(growable: false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    final historyState = ref.watch(aiHistoryProvider);
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text(L10n.of(context).conversationHistory),
            trailing: DeleteConfirm(
              delete: () => _confirmClearHistory(context),
              deleteIcon: Icon(Icons.delete_sweep),
            ),
          ),
          Expanded(
            child: historyState.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(L10n.of(context).noConversationTip),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return _buildHistoryTile(context, entry);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text(L10n.of(context).failedToLoadHistoryTip),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, AiChatHistoryEntry entry) {
    final provider = _providerByIdFromPrefs(entry.serviceId) ??
        _providerById(entry.serviceId);
    final statusColor =
        entry.completed ? Colors.green : Theme.of(context).colorScheme.tertiary;
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return FilledContainer(
      margin: EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.all(8),
      radius: 15,
      child: GestureDetector(
        onTap: () => _handleHistoryTap(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _formatTimestamp(entry.updatedAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    DeleteConfirm(
                        delete: () => _confirmDeleteHistory(context, entry)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildHistorySubtitle(
    AiProviderMeta? provider,
    AiChatHistoryEntry entry,
  ) {
    final serviceLabel = provider?.name ?? entry.serviceId;
    if (entry.model.isEmpty) {
      return serviceLabel;
    }
    return '$serviceLabel · ${entry.model}';
  }

  AiProviderMeta? _providerByIdFromPrefs(String id) {
    return Prefs().getAiProviderMeta(id);
  }

  String _deriveTitle(AiChatHistoryEntry entry) {
    for (final message in entry.messages) {
      if (message is HumanChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    return '$date $time';
  }

  Future<void> _handleHistoryTap(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    if (_isStreaming) {
      _cancelStreaming();
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    final controller = _messageController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _messageController = null;

    ref.read(aiChatProvider.notifier).loadHistoryEntry(entry);

    setState(() {
      _messageStream = null;
      // reset state when switching service
    });

    Navigator.of(context).pop();
    _scrollToBottom();
  }

  Future<void> _confirmDeleteHistory(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    await ref.read(aiHistoryProvider.notifier).remove(entry.id);

    final currentSessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    if (currentSessionId == entry.id) {
      ref.read(aiChatProvider.notifier).clear();
      setState(() {
        _messageStream = null;
        // reset state when conversation changes
      });
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    await ref.read(aiHistoryProvider.notifier).clear();
    ref.read(aiChatProvider.notifier).clear();
    setState(() {
      _messageStream = null;
    });
  }

  void _startStream(Stream<List<ChatMessage>> stream) {
    _messageSubscription?.cancel();
    _messageController?.close();

    final controller = StreamController<List<ChatMessage>>();

    setState(() {
      _messageController = controller;
      _messageStream = controller.stream;
      _isStreaming = true;
    });

    _messageSubscription = stream.listen(
      (event) {
        controller.add(event);
        _scrollToBottom();
      },
      onError: (error, stack) {
        controller.addError(error, stack);
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      },
      cancelOnError: false,
    );
  }

  void _sendMessage() {
    if (_isStreaming) {
      return;
    }

    if (inputController.text.trim().isEmpty) return;
    final message = inputController.text.trim();
    inputController.clear();

    final stream = ref.read(aiChatProvider.notifier).sendMessageStream(
          message,
          ref,
          false,
        );

    _startStream(stream);
  }

  void _regenerateFromUserIndex(int userIndex) {
    if (_isStreaming) {
      return;
    }

    final stream = ref.read(aiChatProvider.notifier).sendMessageStream(
          '',
          ref,
          true,
          regenerateFromUserIndex: userIndex,
        );

    _startStream(stream);
  }

  void _editUserMessageAndRegenerate(int userIndex, String newText) {
    if (_isStreaming) {
      return;
    }

    final stream = ref.read(aiChatProvider.notifier).sendMessageStream(
          newText,
          ref,
          true,
          regenerateFromUserIndex: userIndex,
          replaceUserMessage: true,
        );

    _startStream(stream);
  }

  void _copyPlainText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  Future<void> _confirmRegenerateFromUserIndex(
    int userIndex, {
    required bool isLastTurn,
  }) async {
    if (_isStreaming) {
      return;
    }

    if (!isLastTurn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatRegenerateFromHereConfirmTitle),
            content: Text(L10n.of(context).aiChatRegenerateFromHereConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
    }

    _regenerateFromUserIndex(userIndex);
  }

  Future<void> _showEditUserMessageDialog(
    int userIndex,
    String currentText,
  ) async {
    if (_isStreaming) {
      return;
    }

    final controller = TextEditingController(text: currentText);
    try {
      final edited = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatEditUserMessageTitle),
            content: TextField(
              controller: controller,
              maxLength: 20000,
              maxLines: 6,
              minLines: 1,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(controller.text.trim());
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          );
        },
      );

      if (edited == null) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatRegenerateFromHereConfirmTitle),
            content: Text(L10n.of(context).aiChatRegenerateFromHereConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      _editUserMessageAndRegenerate(userIndex, edited);
    } finally {
      controller.dispose();
    }
  }

  void _useQuickPrompt(String prompt) {
    inputController.text = '$prompt ${inputController.text}';
    _sendMessage();
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      ref.read(aiChatProvider.notifier).clear();
      _messageStream = null;
      _suggestedPrompts = _pickSuggestedPrompts();
    });
  }

  void _regenerateLastMessage() {
    if (_isStreaming) {
      return;
    }
    final messages = ref.read(aiChatProvider).value;
    if (messages == null || messages.isEmpty) {
      return;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        _regenerateFromUserIndex(i);
        break;
      }
    }
  }

  void _copyMessageContent(String content) {
    final parsed = parseReasoningContent(content);
    final clipboardText = _buildCopyableText(parsed, content);
    Clipboard.setData(ClipboardData(text: clipboardText));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  void _cancelStreaming() {
    if (!_isStreaming) return;
    cancelActiveAiRequest();
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      _isStreaming = false;
      _messageStream = null;
    });
  }

  ChatMessage? _getLastAssistantMessage() {
    final messages = ref.watch(aiChatProvider).asData?.value;
    if (messages == null || messages.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is AIChatMessage) {
        return messages[i];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final quickPrompts = _getQuickPrompts(context);

    final current = _currentProvider;
    final currentModel = _modelLabel(_selectedProviderId);

    var aiService = PopupMenuButton<String>(
      enabled: !_isStreaming,
      onSelected: _onProviderSelected,
      itemBuilder: (context) {
        return _providers.map((provider) {
          final isSelected = provider.id == _selectedProviderId;
          final model = _modelLabel(provider.id);
          final logoKey = _providerLogoKey(provider);

          final label =
              model.isEmpty ? provider.name : '${provider.name} · $model';

          return PopupMenuItem<String>(
            value: provider.id,
            enabled: provider.enabled,
            child: Row(
              children: [
                if (logoKey.isNotEmpty)
                  Image.asset(
                    logoKey,
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  )
                else
                  const SizedBox(width: 20, height: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) const Icon(Icons.check, size: 16),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            _providerLogoKey(current),
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentModel.isEmpty
                  ? current.name
                  : '${current.name} · $currentModel',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
    Widget inputBox = FilledContainer(
      padding: const EdgeInsets.all(4),
      radius: 15,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox.shrink(),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      spacing: 8,
                      children: quickPrompts.map((prompt) {
                        return ActionChip(
                          // labelPadding: EdgeInsets.all(0),
                          label: Text(prompt['label']!),
                          onPressed: () => _useQuickPrompt(prompt['prompt']!),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            TextField(
              controller: inputController,
              decoration: InputDecoration(
                isDense: true,
                hintText: L10n.of(context).aiHintInputPlaceholder,
                border: InputBorder.none,
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: aiService),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(
                          _thinkingIcon(
                            _thinkingModeForProvider(_selectedProviderId),
                          ),
                          size: 18,
                        ),
                        tooltip: L10n.of(context).aiThinkingTitle,
                        onPressed: _editThinkingMode,
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune, size: 18),
                        tooltip: L10n.of(context).aiChatEditModelTitle,
                        onPressed: _editCurrentModel,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_isStreaming ? Icons.stop : Icons.send, size: 18),
                  onPressed: _isStreaming ? _cancelStreaming : _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Widget buildEmptyState() {
      final theme = Theme.of(context);

      Widget buildQuickChipColumn() {
        if (widget.quickPromptChips.isEmpty) {
          return const SizedBox.shrink();
        }

        final chips = <Widget>[];
        for (var i = 0; i < widget.quickPromptChips.length; i++) {
          final chip = widget.quickPromptChips[i];
          chips.add(
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8.0),
              child: ActionChip(
                avatar: Icon(chip.icon, size: 18),
                label: Text(chip.label),
                onPressed: () {
                  inputController.text = chip.prompt;
                  _sendMessage();
                },
              ),
            ),
          );
        }

        return Positioned(
          right: 16,
          bottom: 16,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: SingleChildScrollView(
              // scrollDirection: Axis.horizontal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: chips,
              ),
            ),
          ),
        );
      }

      return Stack(
        children: [
          if (widget.quickPromptChips.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).tryAQuickPrompt,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedPrompts
                        .map(
                          (prompt) => ActionChip(
                            label: Text(prompt),
                            onPressed: () {
                              inputController.text = prompt;
                              _sendMessage();
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          buildQuickChipColumn(),
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(L10n.of(context).aiChat),
        leading: IconButton(
          icon: const Icon(Icons.insert_drive_file),
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_document),
            onPressed: _clearMessage,
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messageStream != null
                ? StreamBuilder<List<ChatMessage>>(
                    stream: _messageStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Skeletonizer.zone(child: Bone.multiText());
                      }

                      final messages = snapshot.data!;
                      if (messages.isEmpty) {
                        return buildEmptyState();
                      }

                      return _buildMessageList(messages);
                    },
                  )
                : ref.watch(aiChatProvider).when(
                      data: (messages) {
                        if (messages.isEmpty) {
                          return buildEmptyState();
                        }

                        return _buildMessageList(messages);
                      },
                      loading: () => Skeletonizer.zone(child: Bone.multiText()),
                      error: (error, stack) =>
                          Center(child: Text('error: $error')),
                    ),
          ),
          inputBox,
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    final lastHumanIndex = _findLastHumanIndex(messages);

    return ListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isStreaming =
            _messageStream != null && index == messages.length - 1;
        return _buildLinearMessageItem(
          messages,
          message,
          index,
          isStreaming,
          lastHumanIndex: lastHumanIndex,
        );
      },
    );
  }

  List<_ChatItem> _buildChatItems(List<ChatMessage> messages) {
    final items = <_ChatItem>[];
    var i = 0;
    while (i < messages.length) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        items.add(_UserChatItem(index: i, message: message));

        final variants = <AIChatMessage>[];
        var j = i + 1;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        if (variants.isNotEmpty) {
          items.add(
            _AssistantGroupChatItem(
              groupKey: i,
              userIndex: i,
              variants: variants,
            ),
          );
        }
        i = j;
        continue;
      }

      if (message is AIChatMessage) {
        // Orphan assistant messages (should be rare). Group them to keep the UI
        // consistent.
        final variants = <AIChatMessage>[];
        var j = i;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        items.add(
          _AssistantGroupChatItem(
            groupKey: -(i + 1),
            userIndex: null,
            variants: variants,
          ),
        );
        i = j;
        continue;
      }

      i++;
    }

    return items;
  }

  int? _findLastHumanIndex(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  int? _findPrevHumanIndex(List<ChatMessage> messages, int fromIndex) {
    for (var i = fromIndex; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  Widget _buildVariantSwitcher(
    int messageIndex,
    bool isStreaming,
  ) {
    final notifier = ref.read(aiChatProvider.notifier);
    final count = notifier.variantCountForMessageIndex(messageIndex);
    if (count <= 1) {
      return const SizedBox.shrink();
    }

    final selected = notifier.selectedVariantIndexForMessageIndex(messageIndex);
    final canNavigate = !_isStreaming && !isStreaming;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: canNavigate && selected > 0
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    -1,
                    ref,
                  );
                }
              : null,
        ),
        Text('${selected + 1}/$count'),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: canNavigate && selected < count - 1
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    1,
                    ref,
                  );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildLinearMessageItem(
    List<ChatMessage> allMessages,
    ChatMessage message,
    int index,
    bool isStreaming, {
    required int? lastHumanIndex,
  }) {
    final isUser = message is HumanChatMessage;
    final content = message.contentAsString;
    final isLongMessage = content.length > 300;

    final prevHumanIndex =
        isUser ? index : _findPrevHumanIndex(allMessages, index);
    final isLastTurn =
        prevHumanIndex != null && prevHumanIndex == lastHumanIndex;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8.0,
        left: isUser ? 8.0 : 0,
        right: isUser ? 0 : 8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.surfaceContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? const Radius.circular(12) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(12),
                  bottomLeft: isUser ? Radius.zero : const Radius.circular(12),
                  bottomRight: isUser ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? _buildCollapsibleText(content, isLongMessage)
                      : _buildAssistantSections(content, isStreaming),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildVariantSwitcher(index, isStreaming),
                      const SizedBox(width: 4),
                      if (isUser) ...[
                        TextButton(
                          onPressed: () => _showEditUserMessageDialog(
                            index,
                            content,
                          ),
                          child: Text(L10n.of(context).commonEdit),
                        ),
                        TextButton(
                          onPressed: () => _copyPlainText(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                      ] else ...[
                        if (prevHumanIndex != null)
                          TextButton(
                            onPressed: () => _confirmRegenerateFromUserIndex(
                              prevHumanIndex,
                              isLastTurn: isLastTurn,
                            ),
                            child: Text(L10n.of(context).aiRegenerate),
                          ),
                        TextButton(
                          onPressed: () => _copyMessageContent(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildUserMessageItem(_UserChatItem item) {
    final content = item.message.contentAsString;
    final isLongMessage = content.length > 300;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.zero,
                  bottomLeft: Radius.zero,
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCollapsibleText(content, isLongMessage),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _showEditUserMessageDialog(
                          item.index,
                          content,
                        ),
                        child: Text(L10n.of(context).commonEdit),
                      ),
                      TextButton(
                        onPressed: () => _copyPlainText(content),
                        child: Text(L10n.of(context).commonCopy),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAssistantGroupItem(
    _AssistantGroupChatItem item, {
    required int? lastHumanIndex,
    required ChatMessage? lastMessage,
  }) {
    var selected = _selectedVariantByUserIndex[item.groupKey] ??
        (item.variants.length - 1);
    if (selected < 0) selected = 0;
    if (selected >= item.variants.length) selected = item.variants.length - 1;

    final message = item.variants[selected];
    final content = message.contentAsString;
    final isStreaming =
        _messageStream != null && identical(lastMessage, message);

    final canNavigateVariants =
        item.variants.length > 1 && !_isStreaming && !isStreaming;

    final isLastTurn =
        item.userIndex != null && item.userIndex == lastHumanIndex;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAssistantSections(content, isStreaming),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.variants.length > 1)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left, size: 18),
                              onPressed: canNavigateVariants && selected > 0
                                  ? () {
                                      setState(() {
                                        _selectedVariantByUserIndex[
                                            item.groupKey] = selected - 1;
                                      });
                                    }
                                  : null,
                            ),
                            Text('${selected + 1}/${item.variants.length}'),
                            IconButton(
                              icon: const Icon(Icons.chevron_right, size: 18),
                              onPressed: canNavigateVariants &&
                                      selected < item.variants.length - 1
                                  ? () {
                                      setState(() {
                                        _selectedVariantByUserIndex[
                                            item.groupKey] = selected + 1;
                                      });
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      if (item.userIndex != null)
                        TextButton(
                          onPressed: () => _confirmRegenerateFromUserIndex(
                            item.userIndex!,
                            isLastTurn: isLastTurn,
                          ),
                          child: Text(L10n.of(context).aiRegenerate),
                        ),
                      TextButton(
                        onPressed: () => _copyMessageContent(content),
                        child: Text(L10n.of(context).commonCopy),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _buildCopyableText(ParsedReasoning parsed, String fallback) {
    final buffer = StringBuffer();
    var hasWrittenSection = false;

    void startSection() {
      if (hasWrittenSection) {
        buffer.writeln();
      } else {
        hasWrittenSection = true;
      }
    }

    // void appendField(String label, String? value) {
    //   final trimmed = value?.trim();
    //   if (trimmed != null && trimmed.isNotEmpty) {
    //     buffer.writeln('$label: $trimmed');
    //   }
    // }

    for (final entry in parsed.timeline) {
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          final text = entry.text?.trim();
          if (text != null && text.isNotEmpty) {
            startSection();
            buffer.writeln(text);
          }
          break;
        case ParsedReasoningEntryType.tool:
          // final step = entry.toolStep;
          // if (step != null) {
          //   startSection();
          //   buffer.writeln('[${step.name} (${step.status})]');
          //   appendField('Input', step.input);
          //   appendField('Output', step.output);
          //   appendField('Error', step.error);
          // }
          break;
      }
    }

    final copyText = buffer.toString().trimRight();
    if (copyText.isEmpty) {
      return fallback;
    }
    return copyText;
  }

  Widget _buildAssistantSections(String content, bool isStreaming) {
    // Extract the <think>...</think> summary (if any), then parse the rest for
    // answer text + tool steps.
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>');
    final matches = thinkRegex.allMatches(content).toList(growable: false);

    final thinking = matches
        .map((m) => m.group(1))
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('\n')
        .trim();

    final remaining = content.replaceAll(thinkRegex, '').trim();
    final parsed = parseReasoningContent(remaining);

    final answerText = parsed.timeline
        .where((e) => e.type == ParsedReasoningEntryType.reply)
        .map((e) => e.text ?? '')
        .join('')
        .trim();

    final toolSteps = parsed.toolSteps;

    final l10n = L10n.of(context);

    final children = <Widget>[];

    if (answerText.isEmpty) {
      children.add(
        isStreaming
            ? Skeletonizer.zone(child: Bone.multiText())
            : const SizedBox.shrink(),
      );
    } else {
      children.add(
        StyledMarkdown(
          data: answerText,
          selectable: true,
        ),
      );
    }

    if (thinking.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 6),
            title: Text(
              l10n.aiSectionThinking,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            children: [
              StyledMarkdown(
                data: thinking,
                selectable: true,
              ),
            ],
          ),
        ),
      );
    }

    if (toolSteps.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 6),
            title: Text(
              l10n.aiSectionTools,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            children: [
              for (var i = 0; i < toolSteps.length; i++) ...[
                _buildToolTile(toolSteps[i]),
                if (i != toolSteps.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildToolTile(ParsedToolStep step) {
    if (step.name == 'bookshelf_organize') {
      return OrganizeBookshelfStepTile(step: step);
    }
    if (step.name == 'mindmap_draw') {
      return MindmapStepTile(step: step);
    }
    if (step.name == 'apply_book_tags') {
      return ApplyBookTagsStepTile(step: step);
    }
    return ToolStepTile(step: step);
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    if (!isLongMessage) {
      return SelectableText(
        text,
        selectionControls: MaterialTextSelectionControls(),
      );
    }

    return _CollapsibleText(text: text);
  }
}

abstract class _ChatItem {
  const _ChatItem();
}

class _UserChatItem extends _ChatItem {
  const _UserChatItem({
    required this.index,
    required this.message,
  });

  final int index;
  final HumanChatMessage message;
}

class _AssistantGroupChatItem extends _ChatItem {
  const _AssistantGroupChatItem({
    required this.groupKey,
    required this.userIndex,
    required this.variants,
  });

  /// Stable within the current in-memory message list.
  ///
  /// - For normal turns: equals [userIndex].
  /// - For orphan assistant groups: negative.
  final int groupKey;

  /// The index of the user message this assistant group belongs to.
  ///
  /// If null, this is an orphan assistant group.
  final int? userIndex;

  final List<AIChatMessage> variants;
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text});

  final String text;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isExpanded)
          SelectableText(
            widget.text,
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
                selectionControls: MaterialTextSelectionControls(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.surfaceContainer,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Text(_isExpanded
              ? L10n.of(context).aiHintCollapse
              : L10n.of(context).aiHintExpand),
        ),
      ],
    );
  }
}
