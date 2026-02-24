import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
// Inline full-text translation status is shown in Reading Settings.
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class TranslateSetting extends StatefulWidget {
  const TranslateSetting({super.key});

  @override
  State<TranslateSetting> createState() => _TranslateSettingState();
}

class _TranslateSettingState extends State<TranslateSetting> {
  Future<void> _pickLang({
    required bool isFrom,
    required bool isFullText,
  }) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: LangListEnum.values.length,
          itemBuilder: (context, index) {
            final lang = LangListEnum.values[index];
            return ListTile(
              title: Text(lang.getNative(context)),
              subtitle: Text(
                lang.name[0].toUpperCase() + lang.name.substring(1),
              ),
              onTap: () {
                if (isFullText) {
                  if (isFrom) {
                    Prefs().fullTextTranslateFrom = lang;
                  } else {
                    Prefs().fullTextTranslateTo = lang;
                  }
                } else {
                  if (isFrom) {
                    Prefs().translateFrom = lang;
                  } else {
                    Prefs().translateTo = lang;
                  }
                }
                Navigator.pop(context);
                setState(() {});
              },
            );
          },
        );
      },
    );
  }

  Future<void> _pickAiTranslateProvider() async {
    final enabledProviders = Prefs()
        .aiProvidersV1
        .where((p) => p.enabled)
        .toList(growable: false);

    if (enabledProviders.isEmpty) {
      AnxToast.show(L10n.of(context).aiServiceNotConfigured);
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            ListTile(
              title: Text(L10n.of(context).settingsTranslateAiFollowChatProvider),
              subtitle: Text(L10n.of(context)
                  .settingsTranslateAiFollowChatProviderDesc),
              onTap: () {
                Prefs().aiTranslateProviderId = '';
                Navigator.pop(context);
                setState(() {});
              },
            ),
            const Divider(height: 1),
            for (final p in enabledProviders)
              ListTile(
                title: Text(p.name),
                subtitle: Text(_providerTypeLabel(context, p.type)),
                trailing: (Prefs().aiTranslateProviderIdEffective == p.id)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Prefs().aiTranslateProviderId = p.id;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
          ],
        );
      },
    );
  }

  String _providerTypeLabel(BuildContext context, AiProviderType type) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return L10n.of(context).settingsAiProviderCenterTypeOpenAICompatible;
      case AiProviderType.openaiResponses:
        return L10n.of(context).settingsAiProviderCenterTypeOpenAIResponses;
      case AiProviderType.anthropic:
        return L10n.of(context).settingsAiProviderCenterTypeAnthropic;
      case AiProviderType.gemini:
        return L10n.of(context).settingsAiProviderCenterTypeGemini;
    }
  }

  Future<void> _pickAiTranslateModel() async {
    final providerId = Prefs().aiTranslateProviderIdEffective;
    final meta = Prefs().getAiProviderMeta(providerId);

    if (meta == null) {
      AnxToast.show(L10n.of(context).aiServiceNotConfigured);
      return;
    }

    var models = Prefs().getAiModelsCacheV1(providerId)?.models ?? const [];
    var loading = false;

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refresh() async {
              if (loading) return;
              setModalState(() {
                loading = true;
              });

              try {
                final rawConfig = Prefs().getAiConfig(providerId);
                if (rawConfig.isEmpty) {
                  AnxToast.show(L10n.of(context).aiServiceNotConfigured);
                  return;
                }

                final fetched = await AiModelsService.fetchModels(
                  provider: meta,
                  rawConfig: rawConfig,
                );

                if (fetched.isNotEmpty) {
                  Prefs().saveAiModelsCacheV1(providerId, fetched);
                }

                models = fetched;
              } catch (e) {
                AnxToast.show(L10n.of(context).commonFailed);
              } finally {
                setModalState(() {
                  loading = false;
                });
              }
            }

            return SafeArea(
              child: ListView(
                children: [
                  ListTile(
                    title: Text(L10n.of(context)
                        .settingsTranslateAiModelFollowProvider),
                    subtitle: Text(L10n.of(context)
                        .settingsTranslateAiModelFollowProviderDesc),
                    trailing: Prefs().aiTranslateModel.trim().isEmpty
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      Prefs().aiTranslateModel = '';
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(L10n.of(context).settingsTranslateAiModelCustom),
                    subtitle:
                        Text(L10n.of(context).settingsTranslateAiModelCustomDesc),
                    onTap: () async {
                      final controller = TextEditingController(
                        text: Prefs().aiTranslateModel.trim(),
                      );

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(
                              L10n.of(context).settingsTranslateAiModelCustom,
                            ),
                            content: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: L10n.of(context)
                                    .settingsTranslateAiModelCustomHint,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(L10n.of(context).commonCancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(L10n.of(context).commonConfirm),
                              ),
                            ],
                          );
                        },
                      );

                      if (ok == true) {
                        Prefs().aiTranslateModel = controller.text;
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                        setState(() {});
                      }
                    },
                  ),
                  ListTile(
                    leading: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    title: Text(L10n.of(context).commonRefresh),
                    onTap: refresh,
                  ),
                  const Divider(height: 1),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        L10n.of(context).settingsTranslateAiModelEmpty,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final m in models)
                    ListTile(
                      title: Text(m),
                      trailing: (Prefs().aiTranslateModel.trim() == m)
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        Prefs().aiTranslateModel = m;
                        Navigator.pop(context);
                        setState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProviderId = Prefs().aiTranslateProviderIdEffective;
    final providerMeta = Prefs().getAiProviderMeta(effectiveProviderId);
    final providerName = providerMeta?.name ?? effectiveProviderId;

    final model = Prefs().aiTranslateModel.trim();
    final modelLabel = model.isEmpty
        ? L10n.of(context).settingsTranslateAiModelFollowProviderShort
        : model;

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsTranslateAiOnlyTitle),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.hub_outlined),
              title: Text(L10n.of(context).settingsTranslateAiProvider),
              value: Text(providerName.isEmpty
                  ? L10n.of(context).commonNotSet
                  : providerName),
              description: Text(
                L10n.of(context).settingsTranslateAiProviderDesc,
              ),
              onPressed: (_) => _pickAiTranslateProvider(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(L10n.of(context).settingsTranslateAiModel),
              value: Text(modelLabel),
              description: Text(L10n.of(context).settingsTranslateAiModelDesc),
              onPressed: (_) => _pickAiTranslateModel(),
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).underlineTranslation),
          tiles: [
            SettingsTile.switchTile(
              leading: const Icon(Icons.auto_fix_high_outlined),
              title: Text(L10n.of(context).readingPageAutoTranslateSelection),
              initialValue: Prefs().autoTranslateSelection,
              onToggle: (v) {
                setState(() {
                  Prefs().autoTranslateSelection = v;
                });
              },
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.language_outlined),
              title: Text(L10n.of(context).settingsTranslateFrom),
              value: Text(Prefs().translateFrom.getNative(context)),
              onPressed: (_) => _pickLang(isFrom: true, isFullText: false),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.language_outlined),
              title: Text(L10n.of(context).settingsTranslateTo),
              value: Text(Prefs().translateTo.getNative(context)),
              onPressed: (_) => _pickLang(isFrom: false, isFullText: false),
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).fullTextTranslation),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.language_outlined),
              title: Text(L10n.of(context).settingsTranslateFrom),
              value: Text(Prefs().fullTextTranslateFrom.getNative(context)),
              onPressed: (_) => _pickLang(isFrom: true, isFullText: true),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.language_outlined),
              title: Text(L10n.of(context).settingsTranslateTo),
              value: Text(Prefs().fullTextTranslateTo.getNative(context)),
              onPressed: (_) => _pickLang(isFrom: false, isFullText: true),
            ),
            // Background status is shown in Reading Settings.
          ],
        ),
      ],
    );
  }
}
