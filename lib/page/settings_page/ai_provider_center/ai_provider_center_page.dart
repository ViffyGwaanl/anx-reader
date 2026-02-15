import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_detail_page.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class AiProviderCenterPage extends StatefulWidget {
  const AiProviderCenterPage({super.key});

  @override
  State<AiProviderCenterPage> createState() => _AiProviderCenterPageState();
}

class _AiProviderCenterPageState extends State<AiProviderCenterPage> {
  late final List<AiServiceOption> _builtInOptions;
  late final Future<void> _prefsReady;

  static const _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _builtInOptions = buildDefaultAiServices();
    _prefsReady = Prefs().initPrefs().then((_) {
      _ensureProvidersInitialized();
    });
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

  AiServiceOption? _builtInOptionFor(String id) {
    return _builtInOptions.where((o) => o.identifier == id).firstOrNull;
  }

  void _openProvider(AiProviderMeta meta) {
    final option = _builtInOptionFor(meta.id);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiProviderDetailPage(
          provider: meta,
          builtInOption: option,
        ),
      ),
    );
  }

  String _fallbackProviderId(List<AiProviderMeta> providers) {
    // Prefer OpenAI built-in if enabled.
    for (final p in providers) {
      if (p.id == 'openai' && p.enabled) return p.id;
    }
    // Otherwise pick the first enabled.
    for (final p in providers) {
      if (p.enabled) return p.id;
    }
    // Worst case - keep existing behavior.
    return 'openai';
  }

  Future<void> _addProvider() async {
    final l10n = L10n.of(context);

    final nameController = TextEditingController();
    var type = AiProviderType.openaiCompatible;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l10n.settingsAiProviderCenterAddTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.settingsAiProviderCenterProviderNameLabel,
                    hintText: l10n.settingsAiProviderCenterProviderNameHint,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AiProviderType>(
                  value: type,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.settingsAiProviderCenterProviderTypeLabel,
                  ),
                  items: AiProviderType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabel(t, l10n)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (v) {
                    if (v == null) return;
                    type = v;
                  },
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
                child: Text(l10n.commonAdd),
              ),
            ],
          );
        },
      );

      if (ok != true || !mounted) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final name = nameController.text.trim().isEmpty
          ? l10n.settingsAiProviderCenterUntitledProvider
          : nameController.text.trim();

      final meta = AiProviderMeta(
        id: _uuid.v4(),
        name: name,
        type: type,
        enabled: true,
        isBuiltIn: false,
        createdAt: now,
        updatedAt: now,
        logoKey: null,
      );

      setState(() {
        Prefs().upsertAiProviderMeta(meta);
      });

      _openProvider(meta);
    } finally {
      nameController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _prefsReady,
      builder: (context, snapshot) {
        final l10n = L10n.of(context);

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.settingsAiProviderCenterTitle),
            ),
            body: Center(
              child: Text('${l10n.commonFailed}: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.settingsAiProviderCenterTitle),
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final providers = Prefs().aiProvidersV1;
        final selectedId = Prefs().selectedAiService;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.settingsAiProviderCenterTitle),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _addProvider,
            tooltip: l10n.commonAdd,
            child: const Icon(Icons.add),
          ),
          body: ListView.separated(
            itemCount: providers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = providers[index];
              final isSelected = p.id == selectedId;

              return ListTile(
                enabled: p.enabled,
                leading: p.logoKey == null
                    ? const Icon(Icons.hub_outlined)
                    : Image.asset(
                        p.logoKey!,
                        width: 24,
                        height: 24,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.hub_outlined),
                      ),
                title: Text(p.name),
                subtitle: Text(_typeLabel(p.type, l10n)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(Icons.check, size: 18),
                      ),
                    Switch(
                      value: p.enabled,
                      onChanged: (value) {
                        setState(() {
                          Prefs().upsertAiProviderMeta(
                            p.copyWith(
                              enabled: value,
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            ),
                          );

                          if (!value && isSelected) {
                            final next =
                                _fallbackProviderId(Prefs().aiProvidersV1);
                            Prefs().selectedAiService = next;
                          }
                        });
                      },
                    ),
                  ],
                ),
                onTap: () => _openProvider(p),
                onLongPress: () {
                  if (!p.enabled) {
                    return;
                  }
                  setState(() {
                    Prefs().selectedAiService = p.id;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.settingsAiProviderCenterDefaultApplied(p.name),
                      ),
                      duration: const Duration(milliseconds: 800),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  String _typeLabel(AiProviderType type, L10n l10n) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return l10n.settingsAiProviderCenterTypeOpenAICompatible;
      case AiProviderType.anthropic:
        return l10n.settingsAiProviderCenterTypeAnthropic;
      case AiProviderType.gemini:
        return l10n.settingsAiProviderCenterTypeGemini;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
