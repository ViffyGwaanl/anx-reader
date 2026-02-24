import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/iap_page.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:anx_reader/page/settings_page/advanced.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/page/settings_page/home_navigation.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/reading.dart';
import 'package:anx_reader/page/settings_page/storege.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/service/iap/iap_service.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:anx_reader/widgets/settings/theme_mode.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        return Scaffold(
          body: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 60, 0, 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: Text(
                            'Anx',
                            style: TextStyle(
                              fontSize: 130,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 10, 8),
                    child: ChangeThemeMode(),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: webdavSwitch(context, setState, ref),
                  ),
                  const Divider(),
                  // Main settings entries (flattened; previously lived under
                  // “More Settings”).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.home_outlined),
                          title: Text(L10n.of(context).settingsHomeNavigation),
                          subtitle: Text(
                              L10n.of(context).settingsHomeNavigationSubtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) =>
                                    const HomeNavigationSettingsPage(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.color_lens_outlined),
                          title: Text(L10n.of(context).settingsAppearance),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const AppearanceSetting(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.book_rounded),
                          title: Text(L10n.of(context).settingsReading),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const ReadingSettings(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.sync_outlined),
                          title: Text(L10n.of(context).settingsSync),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const SyncSetting(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.translate_outlined),
                          title: Text(L10n.of(context).settingsTranslate),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const TranslateSetting(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.headphones),
                          title: Text(L10n.of(context).settingsNarrate),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const NarrateSettings(),
                              ),
                            );
                          },
                        ),
                        if (EnvVar.enableAIFeature) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.auto_awesome),
                            title: Text(L10n.of(context).settingsAi),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => const AISettings(),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.hub_outlined),
                            title: Text(
                                L10n.of(context).settingsAiProviderCenterTitle),
                            subtitle: Text(
                                L10n.of(context).settingsAiProviderCenterDesc),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) =>
                                      const AiProviderCenterPage(),
                                ),
                              );
                            },
                          ),
                        ],
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.storage_outlined),
                          title: Text(L10n.of(context).storage),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const StorageSettings(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.shield_outlined),
                          title: Text(L10n.of(context).settingsAdvanced),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => const AdvancedSetting(),
                              ),
                            );
                          },
                        ),
                        // Developer Options tile is rendered below (with onTap).
                      ],
                    ),
                  ),
                  if (Prefs().developerOptionsEnabled)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListTile(
                        leading: const Icon(Icons.developer_mode),
                        title: const Text('Developer Options'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (context) =>
                                  const DeveloperOptionsPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  if (EnvVar.enableInAppPurchase)
                    ListTile(
                      title: Text(L10n.of(context).iapPageTitle),
                      leading: const Icon(Icons.star_outline),
                      subtitle: Text(ref.watch(iapProvider).maybeWhen(
                            data: (state) => state.status.title(context),
                            orElse: () => L10n.of(context).iapStatusUnknown,
                          )),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const IAPPage()),
                        );
                      },
                    ),
                  const About(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
