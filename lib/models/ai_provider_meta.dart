import 'dart:convert';

/// Provider type for AI chat backends.
///
/// - [openaiCompatible] covers OpenAI Chat Completions compatible gateways.
/// - [anthropic] covers Anthropic Messages API compatible endpoints.
/// - [gemini] covers Google Gemini (Generative Language) compatible endpoints.
enum AiProviderType {
  /// OpenAI Chat Completions compatible gateways.
  openaiCompatible,

  /// OpenAI Responses API (official).
  openaiResponses,

  /// Anthropic Messages API.
  anthropic,

  /// Google Gemini.
  gemini,
}

AiProviderType aiProviderTypeFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'openai':
    case 'openai_compatible':
    case 'openai-compatible':
    case 'openaiCompatible':
      return AiProviderType.openaiCompatible;
    case 'openai_responses':
    case 'openai-responses':
    case 'responses':
      return AiProviderType.openaiResponses;
    case 'anthropic':
    case 'claude':
      return AiProviderType.anthropic;
    case 'gemini':
    case 'google':
      return AiProviderType.gemini;
    default:
      return AiProviderType.openaiCompatible;
  }
}

String aiProviderTypeToString(AiProviderType type) {
  switch (type) {
    case AiProviderType.openaiCompatible:
      return 'openai';
    case AiProviderType.openaiResponses:
      return 'openai_responses';
    case AiProviderType.anthropic:
      return 'anthropic';
    case AiProviderType.gemini:
      return 'gemini';
  }
}

class AiProviderMeta {
  const AiProviderMeta({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
    this.logoKey,
  });

  final String id;
  final String name;
  final AiProviderType type;
  final bool enabled;
  final bool isBuiltIn;
  final int createdAt;
  final int updatedAt;

  /// Optional asset path or icon key.
  final String? logoKey;

  AiProviderMeta copyWith({
    String? name,
    AiProviderType? type,
    bool? enabled,
    bool? isBuiltIn,
    int? createdAt,
    int? updatedAt,
    String? logoKey,
  }) {
    return AiProviderMeta(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      logoKey: logoKey ?? this.logoKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': aiProviderTypeToString(type),
      'enabled': enabled,
      'isBuiltIn': isBuiltIn,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (logoKey != null) 'logoKey': logoKey,
    };
  }

  factory AiProviderMeta.fromJson(Map<String, dynamic> json) {
    return AiProviderMeta(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: aiProviderTypeFromString(json['type']?.toString() ?? ''),
      enabled: json['enabled'] == true,
      isBuiltIn: json['isBuiltIn'] == true,
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      logoKey: json['logoKey']?.toString(),
    );
  }

  static List<AiProviderMeta> decodeList(String raw) {
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final result = <AiProviderMeta>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        result.add(AiProviderMeta.fromJson(item));
      } else if (item is Map) {
        result.add(
          AiProviderMeta.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }
    return result;
  }

  static String encodeList(List<AiProviderMeta> providers) {
    return jsonEncode(providers.map((p) => p.toJson()).toList(growable: false));
  }
}
