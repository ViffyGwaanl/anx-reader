import 'package:anx_reader/config/shared_preference_provider.dart';
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
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();

    final stored = Prefs().getAiConfig(widget.provider.id);
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
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _save() {
    final map = <String, String>{
      'url': _urlController.text.trim(),
      'model': _modelController.text.trim(),
      'api_key': _apiKeyController.text.trim(),
    };

    Prefs().saveAiConfig(widget.provider.id, map);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  void _applyAsDefault() {
    Prefs().selectedAiService = widget.provider.id;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Applied as default')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stored = Prefs().getAiConfig(widget.provider.id);
    final config = LangchainAiConfig.fromPrefs(widget.provider.id, stored);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.provider.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoRow('ID', widget.provider.id),
          _buildInfoRow('Type', _typeLabel(widget.provider.type)),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'URL (baseUrl or endpoint)',
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Effective baseUrl', config.baseUrl ?? ''),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Model',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'API Key',
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
            child: const Text('Set as default'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _save,
            child: const Text('Save'),
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
