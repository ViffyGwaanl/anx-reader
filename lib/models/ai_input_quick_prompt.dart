import 'dart:convert';

/// A configurable quick prompt chip shown in AI chat input area.
class AiInputQuickPrompt {
  final String id;
  final String label;
  final String prompt;
  final bool enabled;
  final int order;

  const AiInputQuickPrompt({
    required this.id,
    required this.label,
    required this.prompt,
    this.enabled = true,
    this.order = 0,
  });

  factory AiInputQuickPrompt.fromJson(Map<String, dynamic> json) {
    return AiInputQuickPrompt(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'prompt': prompt,
        'enabled': enabled,
        'order': order,
      };

  AiInputQuickPrompt copyWith({
    String? id,
    String? label,
    String? prompt,
    bool? enabled,
    int? order,
  }) {
    return AiInputQuickPrompt(
      id: id ?? this.id,
      label: label ?? this.label,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
    );
  }

  static List<AiInputQuickPrompt> fromJsonList(String jsonStr) {
    if (jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => AiInputQuickPrompt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String toJsonList(List<AiInputQuickPrompt> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}
