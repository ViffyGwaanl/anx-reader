import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:flutter/material.dart';

class AiProviderDetailPage extends StatefulWidget {
  const AiProviderDetailPage({
    super.key,
    required this.provider,
    this.builtInOption,
  });

  final AiProviderMeta provider;
  final AiServiceOption? builtInOption;

  @override
  State<AiProviderDetailPage> createState() => _AiProviderDetailPageState();
}

class _AiProviderDetailPageState extends State<AiProviderDetailPage> {
  late AiProviderMeta _provider;

  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();

    _provider = widget.provider;

    _nameController = TextEditingController(text: _provider.name.trim());

    final stored = Prefs().getAiConfig(_provider.id);
    _urlController = TextEditingController(
      text: (stored['url'] ?? widget.builtInOption?.defaultUrl ?? '').trim(),
    );
    _modelController = TextEditingController(
      text:
          (stored['model'] ?? widget.builtInOption?.defaultModel ?? '').trim(),
    );
    _apiKeyController = TextEditingController(
      text: (stored['api_key'] ?? widget.builtInOption?.defaultApiKey ?? '')
          .trim(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = L10n.of(context);

    final map = <String, String>{
      'url': _urlController.text.trim(),
      'model': _modelController.text.trim(),
      'api_key': _apiKeyController.text.trim(),
    };

    Prefs().saveAiConfig(_provider.id, map);

    if (!_provider.isBuiltIn) {
      final name = _nameController.text.trim();
      if (name.isNotEmpty && name != _provider.name) {
        final updated = _provider.copyWith(
          name: name,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        Prefs().upsertAiProviderMeta(updated);
        _provider = updated;
      }
    }

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.commonSaved)),
    );
  }

  void _applyAsDefault() {
    final l10n = L10n.of(context);
    if (!_provider.enabled) {
      return;
    }
    Prefs().selectedAiService = _provider.id;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.settingsAiProviderCenterDefaultApplied(_provider.name),
        ),
      ),
    );
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

  Future<void> _deleteProvider() async {
    final l10n = L10n.of(context);

    if (_provider.isBuiltIn) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsAiProviderCenterDeleteTitle),
          content: Text(
            l10n.settingsAiProviderCenterDeleteBody(_provider.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    final wasSelected = Prefs().selectedAiService == _provider.id;

    Prefs().deleteAiProviderMeta(_provider.id);
    Prefs().deleteAiConfig(_provider.id);

    if (wasSelected) {
      Prefs().selectedAiService = _fallbackProviderId(Prefs().aiProvidersV1);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final stored = Prefs().getAiConfig(_provider.id);
    final config = LangchainAiConfig.fromPrefs(_provider.id, stored);

    return Scaffold(
      appBar: AppBar(
        title: Text(_provider.name),
        actions: [
          if (!_provider.isBuiltIn)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.commonDelete,
              onPressed: _deleteProvider,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.commonSave,
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoRow('ID', _provider.id),
          _buildInfoRow(
            l10n.settingsAiProviderCenterProviderTypeLabel,
            _typeLabel(_provider.type, l10n),
          ),
          const SizedBox(height: 12),
          if (_provider.isBuiltIn)
            _buildInfoRow(
              l10n.settingsAiProviderCenterProviderNameLabel,
              _provider.name,
            )
          else
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.settingsAiProviderCenterProviderNameLabel,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.settingsAiProviderCenterUrlLabel,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            l10n.settingsAiProviderCenterEffectiveBaseUrlLabel,
            config.baseUrl ?? '',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.settingsAiProviderCenterModelLabel,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.settingsAiProviderCenterApiKeyLabel,
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _applyAsDefault,
            child: Text(l10n.settingsAiProviderCenterSetAsDefault),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
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
