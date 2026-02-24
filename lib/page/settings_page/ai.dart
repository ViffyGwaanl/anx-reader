import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/enums/ai_dock_side.dart';
import 'package:anx_reader/enums/ai_pad_panel_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ai_cache_count.dart';
import 'package:anx_reader/providers/user_prompts.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/page/settings_page/ai_quick_prompts_editor.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:url_launcher/url_launcher.dart';

class AISettings extends ConsumerStatefulWidget {
  const AISettings({super.key});

  @override
  ConsumerState<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends ConsumerState<AISettings> {
  bool showSettings = false;
  int currentIndex = 0;
  late List<Map<String, dynamic>> initialServicesConfig;
  bool _obscureApiKey = true;

  // User prompts state
  String? _expandedUserPromptId;
  final Map<String, TextEditingController> _userPromptNameControllers = {};
  final Map<String, TextEditingController> _userPromptContentControllers = {};

  late final List<AiServiceOption> serviceOptions;
  late List<Map<String, dynamic>> services;

  @override
  void initState() {
    serviceOptions = buildDefaultAiServices();
    services = serviceOptions.map(
      (option) {
        return {
          'identifier': option.identifier,
          'title': option.title,
          'logo': option.logo,
          'config': {
            'url': option.defaultUrl,
            'api_key': option.defaultApiKey,
            'model': option.defaultModel,
          },
        };
      },
    ).toList();
    initialServicesConfig = services
        .map(
          (service) => {
            ...service,
            'config': Map<String, String>.from(
              service['config'] as Map<String, String>,
            ),
          },
        )
        .toList();
    for (final service in services) {
      final stored = Prefs().getAiConfig(service['identifier'] as String);
      final config = service['config'] as Map<String, String>;
      for (final entry in stored.entries) {
        config[entry.key] = entry.value;
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    // Clean up user prompt controllers
    for (var controller in _userPromptNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _userPromptContentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    List<Map<String, dynamic>> prompts = [
      {
        "identifier": AiPrompts.test,
        "title": l10n.settingsAiPromptTest,
        "variables": ["language_locale"],
      },
      {
        "identifier": AiPrompts.summaryTheChapter,
        "title": l10n.settingsAiPromptSummaryTheChapter,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryTheBook,
        "title": l10n.settingsAiPromptSummaryTheBook,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryThePreviousContent,
        "title": l10n.settingsAiPromptSummaryThePreviousContent,
        "variables": ["previous_content"],
      },
      {
        "identifier": AiPrompts.translate,
        "title": l10n.settingsAiPromptTranslateAndDictionary,
        "variables": ["text", "to_locale", "from_locale", "contextText"],
      },
      {
        "identifier": AiPrompts.translateFulltext,
        "title": l10n.settingsAiPromptTranslateFulltext,
        "variables": ["text", "to_locale", "from_locale", "contextText"],
      },
      {
        "identifier": AiPrompts.mindmap,
        "title": l10n.settingsAiPromptMindmap,
        "variables": [],
      }
    ];

    Widget aiConfig() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              services[currentIndex]["title"],
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          CustomSettingsTile(
            child: SettingsTile.navigation(
              title: Text(l10n.settingsAiProviderCenterTitle),
              description: Text(l10n.settingsAiProviderCenterDesc),
              onPressed: (context) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AiProviderCenterPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          for (var key in services[currentIndex]["config"].keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                obscureText: key == "api_key" && _obscureApiKey,
                controller: TextEditingController(
                    text: services[currentIndex]["config"][key] ??
                        initialServicesConfig[currentIndex]["config"][key]),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: key,
                  hintText: services[currentIndex]["config"][key],
                  suffixIcon: key == "api_key"
                      ? IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureApiKey = !_obscureApiKey;
                            });
                          },
                          icon: _obscureApiKey
                              ? const Icon(Icons.visibility_off)
                              : const Icon(Icons.visibility),
                        )
                      : null,
                ),
                onChanged: (value) {
                  services[currentIndex]["config"][key] = value;
                },
              ),
            ),
          CustomSettingsTile(
            child: GestureDetector(
              onTap: () async {
                if (!await launchUrl(
                    Uri.parse('https://anx.anxcye.com/docs/ai/'),
                    mode: LaunchMode.externalApplication)) {
                  AnxToast.show(L10n.of(context).commonFailed);
                }
              },
              child: Text(
                L10n.of(context).settingsNarrateClickForHelp,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  decoration: TextDecoration.underline,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () {
                    Prefs().deleteAiConfig(
                      services[currentIndex]["identifier"],
                    );
                    services[currentIndex]["config"] = Map<String, String>.from(
                        initialServicesConfig[currentIndex]["config"]);
                    setState(() {});
                  },
                  child: Text(L10n.of(context).commonReset)),
              TextButton(
                  onPressed: () {
                    SmartDialog.show(
                      onDismiss: () {
                        cancelActiveAiRequest();
                      },
                      builder: (context) => AlertDialog(
                          title: Text(L10n.of(context).commonTest),
                          content: AiStream(
                              prompt: generatePromptTest(),
                              identifier: services[currentIndex]["identifier"],
                              config: services[currentIndex]["config"],
                              regenerate: true)),
                    );
                  },
                  child: Text(L10n.of(context).commonTest)),
              TextButton(
                  onPressed: () {
                    Prefs().saveAiConfig(
                      services[currentIndex]["identifier"],
                      services[currentIndex]["config"],
                    );

                    setState(() {
                      showSettings = false;
                    });
                  },
                  child: Text(L10n.of(context).commonSave)),
              TextButton(
                  onPressed: () {
                    Prefs().selectedAiService =
                        services[currentIndex]["identifier"];
                    Prefs().saveAiConfig(
                      services[currentIndex]["identifier"],
                      services[currentIndex]["config"],
                    );

                    setState(() {
                      showSettings = false;
                    });
                  },
                  child: Text(L10n.of(context).commonApply)),
            ],
          )
        ],
      );
    }

    final servicesTile = CustomSettingsTile(
      child: SettingsTile.navigation(
        title: Text(l10n.settingsAiProviderCenterTitle),
        description: Text(l10n.settingsAiProviderCenterDesc),
        onPressed: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AiProviderCenterPage(),
            ),
          );
        },
      ),
    );

    var promptTile = CustomSettingsTile(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          return SettingsTile.navigation(
            title: Text(prompts[index]["title"]),
            onPressed: (context) {
              SmartDialog.show(builder: (context) {
                final controller = TextEditingController(
                  text: Prefs().getAiPrompt(
                    AiPrompts.values[index],
                  ),
                );

                return AlertDialog(
                  title: Text(L10n.of(context).commonEdit),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        maxLines: 10,
                        controller: controller,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Wrap(
                        children: [
                          for (var variable in prompts[index]["variables"])
                            TextButton(
                              onPressed: () {
                                // insert the variables at the cursor
                                if (controller.selection.start == -1 ||
                                    controller.selection.end == -1) {
                                  return;
                                }

                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: controller.selection.start,
                                  ),
                                );

                                controller.text = controller.text.replaceRange(
                                  controller.selection.start,
                                  controller.selection.end,
                                  '{{$variable}}',
                                );
                              },
                              child: Text(
                                '{{$variable}}',
                              ),
                            ),
                        ],
                      )
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Prefs().deleteAiPrompt(AiPrompts.values[index]);
                        controller.text = Prefs().getAiPrompt(
                          AiPrompts.values[index],
                        );
                      },
                      child: Text(L10n.of(context).commonReset),
                    ),
                    TextButton(
                      onPressed: () {
                        Prefs().saveAiPrompt(
                          AiPrompts.values[index],
                          controller.text,
                        );
                      },
                      child: Text(L10n.of(context).commonSave),
                    ),
                  ],
                );
              });
            },
          );
        },
      ),
    );

    final toolDefs = AiToolRegistry.definitions;
    final enabledToolIds = Prefs().enabledAiToolIds;

    final toolsTile = CustomSettingsTile(
      child: Column(
        children: [
          for (final tool in toolDefs)
            SettingsTile.switchTile(
              initialValue: enabledToolIds.contains(tool.id),
              onToggle: (value) {
                final next = Set<String>.from(enabledToolIds);
                if (value) {
                  next.add(tool.id);
                } else {
                  next.remove(tool.id);
                }
                Prefs().enabledAiToolIds = next.toList();
                setState(() {});
              },
              title: Text(tool.displayName(l10n)),
              description: Text(tool.description(l10n)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Prefs().resetEnabledAiTools();
                setState(() {});
              },
              child: Text(l10n.commonReset),
            ),
          ),
        ],
      ),
    );

    return settingsSections(sections: [
      SettingsSection(
        title: Text(L10n.of(context).settingsAiServices),
        tiles: [
          servicesTile,
          // SettingsTile.navigation(
          //   leading: const Icon(Icons.chat),
          //   title: Text(L10n.of(context).aiChat),
          //   onPressed: (context) {
          //     Navigator.push(
          //       context,
          //       CupertinoPageRoute(
          //         builder: (context) => const AiChatPage(),
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiPrompt),
        tiles: [
          promptTile,
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiUserPrompts),
        tiles: [
          userPromptsTile(),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiTools),
        tiles: [
          toolsTile,
        ],
      ),
      // iPad-specific AI panel settings (only show on larger screens)
      if (MediaQuery.of(context).size.width >= 600)
        SettingsSection(
          title: Text(l10n.settingsAiPadPanelMode),
          tiles: [
            SettingsTile.switchTile(
              title: Text(l10n.settingsAiPadPanelModeBottomSheet),
              description: Text(l10n.settingsAiPadPanelModeDock),
              initialValue:
                  Prefs().aiPadPanelMode == AiPadPanelModeEnum.bottomSheet,
              onToggle: (value) {
                setState(() {
                  Prefs().aiPadPanelMode = value
                      ? AiPadPanelModeEnum.bottomSheet
                      : AiPadPanelModeEnum.dock;
                });
              },
            ),
            // Dock side only relevant when in dock mode
            if (Prefs().aiPadPanelMode == AiPadPanelModeEnum.dock)
              SettingsTile.navigation(
                title: Text(l10n.settingsAiDockSide),
                value: Text(Prefs().aiDockSide == AiDockSideEnum.left
                    ? l10n.settingsAiDockSideLeft
                    : l10n.settingsAiDockSideRight),
                onPressed: (context) {
                  setState(() {
                    Prefs().aiDockSide =
                        Prefs().aiDockSide == AiDockSideEnum.left
                            ? AiDockSideEnum.right
                            : AiDockSideEnum.left;
                  });
                },
              ),
          ],
        ),
      SettingsSection(
        title: Text(l10n.settingsAiQuickPrompts),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.settingsAiQuickPrompts),
            description: Text(l10n.settingsAiQuickPromptsHint),
            onPressed: (context) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AiQuickPromptsEditor(),
                ),
              );
            },
          ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiCache),
        tiles: [
          CustomSettingsTile(
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(L10n.of(context).settingsAiCacheSize),
                  Text(
                    L10n.of(context).settingsAiCacheCurrentSize(ref
                        .watch(aiCacheCountProvider)
                        .when(
                            data: (value) => value,
                            loading: () => 0,
                            error: (error, stack) => 0)),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Text(Prefs().maxAiCacheCount.toString()),
                  Expanded(
                    child: Slider(
                      value: Prefs().maxAiCacheCount.toDouble(),
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: Prefs().maxAiCacheCount.toString(),
                      onChanged: (value) {
                        Prefs().maxAiCacheCount = value.toInt();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAiCacheClear),
              onPressed: (context) {
                SmartDialog.show(
                  builder: (context) => AlertDialog(
                    title: Text(L10n.of(context).commonConfirm),
                    actions: [
                      TextButton(
                        onPressed: () {
                          SmartDialog.dismiss();
                        },
                        child: Text(L10n.of(context).commonCancel),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(aiCacheCountProvider.notifier).clearCache();
                          SmartDialog.dismiss();
                        },
                        child: Text(L10n.of(context).commonConfirm),
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiDebugTitle),
        tiles: [
          SettingsTile.switchTile(
            leading: const Icon(Icons.developer_mode),
            title: Text(l10n.settingsAiDebugEnable),
            description: Text(l10n.settingsAiDebugEnableDesc),
            initialValue: Prefs().aiDebugLogsEnabled,
            onToggle: (value) {
              setState(() {
                Prefs().aiDebugLogsEnabled = value;
              });
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.bug_report),
            title: Text(L10n.of(context).settingsAdvancedLog),
            onPressed: (context) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LogPage()),
              );
            },
          ),
        ],
      ),
    ]);
  }

  // User prompts management methods
  AbstractSettingsTile userPromptsTile() {
    final userPrompts = ref.watch(userPromptsProvider);
    ref.read(userPromptsProvider.notifier);

    return CustomSettingsTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top button and hint
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnxButton(
                  onPressed: _showAddPromptDialog,
                  child: Text(L10n.of(context).settingsAiUserPromptsAdd),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        L10n.of(context).settingsAiUserPromptsHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Prompts list
          if (userPrompts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  L10n.of(context).settingsAiUserPromptsEmpty,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: userPrompts.length,
              itemBuilder: (context, index) {
                final prompt = userPrompts[index];
                final isExpanded = _expandedUserPromptId == prompt.id;

                return _buildUserPromptItem(
                  prompt,
                  isExpanded,
                  index,
                  userPrompts.length,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserPromptItem(
    prompt,
    bool isExpanded,
    int index,
    int totalCount,
  ) {
    final notifier = ref.read(userPromptsProvider.notifier);

    // Initialize controllers
    _userPromptNameControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.name),
    );
    _userPromptContentControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.content),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withAlpha(100)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: Switch + Name + Action buttons
            Row(
              children: [
                Switch(
                  value: prompt.enabled,
                  onChanged: (_) {
                    notifier.toggleEnabled(prompt.id);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prompt.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Edit button
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.edit),
                  onPressed: () {
                    setState(() {
                      _expandedUserPromptId = isExpanded ? null : prompt.id;
                    });
                  },
                  tooltip: L10n.of(context).commonEdit,
                ),

                // Move up button
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: index > 0
                      ? () => notifier.movePrompt(prompt.id, true)
                      : null,
                ),

                // Move down button
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  onPressed: index < totalCount - 1
                      ? () => notifier.movePrompt(prompt.id, false)
                      : null,
                ),
              ],
            ),

            // Expanded edit area
            if (isExpanded) ...[
              const Divider(height: 16),
              _buildEditForm(prompt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(prompt) {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = _userPromptNameControllers[prompt.id]!;
    final contentController = _userPromptContentControllers[prompt.id]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name input
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsName,
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        const SizedBox(height: 12),

        // Content input
        TextField(
          controller: contentController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsContent,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 8,
          minLines: 5,
          maxLength: 20000,
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Delete button (uses default L10n text)
            DeleteConfirm(
              delete: () {
                notifier.deletePrompt(prompt.id);
                _userPromptNameControllers.remove(prompt.id)?.dispose();
                _userPromptContentControllers.remove(prompt.id)?.dispose();
                setState(() {
                  _expandedUserPromptId = null;
                });
              },
              useTextButton: true,
            ),

            // Save button
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                final content = contentController.text.trim();

                if (name.isEmpty || content.isEmpty) {
                  AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                  return;
                }

                final updatedPrompt = prompt.copyWith(
                  name: name,
                  content: content,
                );
                notifier.updatePrompt(updatedPrompt);

                setState(() {
                  _expandedUserPromptId = null;
                });

                AnxToast.show(L10n.of(context).commonSaveSuccess);
              },
              child: Text(L10n.of(context).commonSave),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddPromptDialog() {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = TextEditingController();
    final contentController = TextEditingController();

    SmartDialog.show(
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).settingsAiUserPromptsAdd),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsName,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 50,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsContent,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 5,
                maxLength: 20000,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();
            },
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final content = contentController.text.trim();

              if (name.isEmpty || content.isEmpty) {
                AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                return;
              }

              notifier.addPrompt(name: name, content: content);

              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();

              AnxToast.show(L10n.of(context).commonAddSuccess);
            },
            child: Text(L10n.of(context).commonConfirm),
          ),
        ],
      ),
    );
  }
}
