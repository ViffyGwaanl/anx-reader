import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class HomeNavigationSettingsPage extends StatefulWidget {
  const HomeNavigationSettingsPage({super.key});

  @override
  State<HomeNavigationSettingsPage> createState() =>
      _HomeNavigationSettingsPageState();
}

class _HomeNavigationSettingsPageState
    extends State<HomeNavigationSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final order = Prefs().homeTabsOrder;
        final enabled = Prefs().homeTabsEnabled;

        String titleOf(String id) {
          switch (id) {
            case Prefs.homeTabPapers:
              return L10n.of(context).navBarPapers;
            case Prefs.homeTabBookshelf:
              return L10n.of(context).navBarBookshelf;
            case Prefs.homeTabStatistics:
              return L10n.of(context).navBarStatistics;
            case Prefs.homeTabAI:
              return L10n.of(context).navBarAI;
            case Prefs.homeTabNotes:
              return L10n.of(context).navBarNotes;
            case Prefs.homeTabSettings:
              return L10n.of(context).navBarSettings;
            default:
              return id;
          }
        }

        IconData iconOf(String id) {
          switch (id) {
            case Prefs.homeTabPapers:
              return Icons.article_outlined;
            case Prefs.homeTabBookshelf:
              return Icons.book_outlined;
            case Prefs.homeTabStatistics:
              return Icons.show_chart;
            case Prefs.homeTabAI:
              return Icons.auto_awesome;
            case Prefs.homeTabNotes:
              return Icons.note_outlined;
            case Prefs.homeTabSettings:
              return Icons.settings_outlined;
            default:
              return Icons.circle_outlined;
          }
        }

        bool isMandatory(String id) {
          return id == Prefs.homeTabPapers || id == Prefs.homeTabSettings;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(L10n.of(context).settingsHomeNavigation),
            actions: [
              TextButton(
                onPressed: () {
                  Prefs().resetHomeTabsConfigToDefault();
                },
                child: Text(
                  L10n.of(context).commonReset,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  L10n.of(context).settingsHomeNavigationSubtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: order.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final next = [...order];
                    final item = next.removeAt(oldIndex);
                    next.insert(newIndex, item);
                    Prefs().setHomeTabsOrder(next);
                  },
                  itemBuilder: (context, index) {
                    final id = order[index];
                    final mandatory = isMandatory(id);
                    final value = enabled[id] ?? true;

                    return ListTile(
                      key: ValueKey(id),
                      leading: Icon(iconOf(id)),
                      title: Text(titleOf(id)),
                      subtitle: null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!mandatory)
                            Switch(
                              value: value,
                              onChanged: (v) {
                                Prefs().setHomeTabEnabled(id, v);
                              },
                            )
                          else
                            const Icon(Icons.lock_outline),
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8.0),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
