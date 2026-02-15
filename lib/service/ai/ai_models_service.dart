import 'dart:convert';

import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:dio/dio.dart';

class AiModelsService {
  static final Dio _dio = Dio();

  static String registryIdentifierFor(AiProviderMeta provider) {
    switch (provider.type) {
      case AiProviderType.anthropic:
        return 'claude';
      case AiProviderType.gemini:
        return 'gemini';
      case AiProviderType.openaiCompatible:
        return 'openai';
    }
  }

  /// Fetch model ids for the provider.
  ///
  /// Note: This is best-effort. Some gateways may not support listing models.
  static Future<List<String>> fetchModels({
    required AiProviderMeta provider,
    required Map<String, String> rawConfig,
  }) async {
    final registryId = registryIdentifierFor(provider);
    final config = LangchainAiConfig.fromPrefs(registryId, rawConfig);

    switch (provider.type) {
      case AiProviderType.openaiCompatible:
        return _fetchOpenAICompatible(config);
      case AiProviderType.anthropic:
        return _fetchAnthropic(config);
      case AiProviderType.gemini:
        return _fetchGemini(config);
    }
  }

  static Future<List<String>> _fetchOpenAICompatible(
      LangchainAiConfig config) async {
    final baseUrl = config.baseUrl ?? 'https://api.openai.com/v1';
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);
    if (config.apiKey.isNotEmpty && !headers.containsKey('Authorization')) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final res = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map && decoded['data'] is List) {
      final list = decoded['data'] as List;
      return list
          .map((e) => e is Map ? e['id']?.toString() : null)
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
    }

    return const [];
  }

  static Future<List<String>> _fetchAnthropic(LangchainAiConfig config) async {
    final baseUrl = config.baseUrl ?? 'https://api.anthropic.com/v1';
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);

    // Anthropic requires x-api-key and anthropic-version.
    if (config.apiKey.isNotEmpty && !headers.containsKey('x-api-key')) {
      headers['x-api-key'] = config.apiKey;
    }
    headers.putIfAbsent('anthropic-version', () => '2023-06-01');

    final res = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map && decoded['data'] is List) {
      final list = decoded['data'] as List;
      return list
          .map((e) => e is Map ? e['id']?.toString() : null)
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
    }

    return const [];
  }

  static Future<List<String>> _fetchGemini(LangchainAiConfig config) async {
    final rawBase =
        config.baseUrl ?? 'https://generativelanguage.googleapis.com';

    // Gemini model listing endpoint:
    // GET https://generativelanguage.googleapis.com/v1beta/models
    // Auth via query param key=... or header x-goog-api-key.
    final baseUri = Uri.tryParse(rawBase);
    final hasV1Beta =
        baseUri != null && baseUri.pathSegments.contains('v1beta');
    final baseUrl = hasV1Beta ? rawBase : _join(rawBase, 'v1beta');
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);
    if (config.apiKey.isNotEmpty && !headers.containsKey('x-goog-api-key')) {
      headers['x-goog-api-key'] = config.apiKey;
    }

    final uri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        if (config.apiKey.isNotEmpty) 'key': config.apiKey,
      },
    );

    final res = await _dio.get(
      uri.toString(),
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;

    if (decoded is Map && decoded['models'] is List) {
      final list = decoded['models'] as List;
      final ids = <String>{};
      for (final item in list) {
        if (item is Map) {
          final name = item['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          // Normalize 'models/gemini-1.5-pro' -> 'gemini-1.5-pro'
          final normalized = name.startsWith('models/')
              ? name.substring('models/'.length)
              : name;
          if (normalized.trim().isNotEmpty) {
            ids.add(normalized.trim());
          }
        }
      }
      final result = ids.toList(growable: false)..sort();
      return result;
    }

    return const [];
  }

  static String _join(String baseUrl, String path) {
    if (baseUrl.endsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
}
