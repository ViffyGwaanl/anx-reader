import 'package:anx_reader/config/shared_preference_provider.dart';
// l10n import intentionally omitted
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_detail_page.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:flutter/material.dart';

class AiProviderCenterPage extends StatefulWidget {
  const AiProviderCenterPage({super.key});

  @override
  State<AiProviderCenterPage> createState() => _AiProviderCenterPageState();
}

class _AiProviderCenterPageState extends State<AiProviderCenterPage> {
  late final List<AiServiceOption> _builtInOptions;
  late final Future<void> _prefsReady;

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _prefsReady,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('供应商中心'),
            ),
            body: Center(
              child: Text('加载失败：${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('供应商中心'),
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
            title: const Text('供应商中心'),
          ),
          body: ListView.separated(
            itemCount: providers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = providers[index];
              final isSelected = p.id == selectedId;

              return ListTile(
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
                subtitle: Text(_typeLabel(p.type)),
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
                      content: Text('已设为默认：${p.name}'),
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

  String _typeLabel(AiProviderType type) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return 'OpenAI-compatible';
      case AiProviderType.anthropic:
        return 'Anthropic';
      case AiProviderType.gemini:
        return 'Gemini';
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
