import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_dock_side.dart';
import 'package:anx_reader/enums/ai_pad_panel_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/models/ai_input_quick_prompt.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/utils/log/common.dart';

const int aiSettingsSchemaVersion = 1;

/// Build a JSON-serializable AI settings snapshot for sync.
///
/// Security:
/// - MUST NOT include api keys.
Map<String, dynamic> buildLocalAiSettingsJson() {
  final prefs = Prefs();

  final services = <String, dynamic>{};
  for (final option in buildDefaultAiServices()) {
    final id = option.identifier;
    final stored = prefs.getAiConfig(id);
    if (stored.isEmpty) continue;

    // Remove secrets.
    final safe = Map<String, dynamic>.from(stored);
    safe.remove('api_key');

    // Only keep non-empty values.
    safe.removeWhere((k, v) => v == null || v.toString().trim().isEmpty);
    if (safe.isEmpty) continue;

    services[id] = safe;
  }

  final prompts = <String, dynamic>{};
  for (final p in AiPrompts.values) {
    final current = prefs.getAiPrompt(p);
    final defaultPrompt = p.getPrompt();
    if (current != defaultPrompt) {
      prompts[p.name] = current;
    }
  }

  final ui = <String, dynamic>{
    'aiPadPanelMode': prefs.aiPadPanelMode.code,
    'aiDockSide': prefs.aiDockSide.code,
    'aiPanelPosition': prefs.aiPanelPosition.code,
    'aiPanelWidth': prefs.aiPanelWidth,
    'aiPanelHeight': prefs.aiPanelHeight,
    'aiSheetInitialSize': prefs.aiSheetInitialSize,
    'aiChatFontScale': prefs.aiChatFontScale,
  };

  // Translation-only prefs (safe to sync; no secrets).
  final translate = <String, dynamic>{
    'aiTranslateProviderIdV1': prefs.aiTranslateProviderId,
    'aiTranslateModelV1': prefs.aiTranslateModel,
    'inlineFullTextTranslateConcurrency':
        prefs.inlineFullTextTranslateConcurrency,
  };

  return {
    'schemaVersion': aiSettingsSchemaVersion,
    'updatedAt': prefs.aiSettingsUpdatedAt,
    'selectedServiceId': prefs.selectedAiService,
    'services': services,
    'prompts': prompts,
    'userPrompts': prefs.userPrompts.map((e) => e.toJson()).toList(),
    'inputQuickPrompts':
        prefs.aiInputQuickPrompts.map((e) => e.toJson()).toList(),
    'ui': ui,
    'translate': translate,
  };
}

/// Apply an AI settings snapshot into local prefs.
///
/// Note: api keys are preserved from local storage.
void applyAiSettingsJson(Map<String, dynamic> json) {
  final prefs = Prefs();

  final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
  if (schemaVersion != aiSettingsSchemaVersion) {
    AnxLog.info('ai_settings_sync: unsupported schemaVersion=$schemaVersion');
    return;
  }

  final updatedAt = (json['updatedAt'] as num?)?.toInt() ?? 0;

  try {
    final selectedServiceId = json['selectedServiceId'] as String?;
    if (selectedServiceId != null && selectedServiceId.trim().isNotEmpty) {
      prefs.selectedAiService = selectedServiceId;
    }

    final services = json['services'];
    if (services is Map) {
      for (final entry in services.entries) {
        final id = entry.key.toString();
        final remoteConfig = entry.value;
        if (remoteConfig is! Map) continue;

        final current = prefs.getAiConfig(id);
        final apiKey = current['api_key'];

        final merged = <String, String>{};
        for (final e in remoteConfig.entries) {
          merged[e.key.toString()] = e.value?.toString() ?? '';
        }

        // Ensure api_key remains local-only.
        if (apiKey != null && apiKey.trim().isNotEmpty) {
          merged['api_key'] = apiKey;
        }

        prefs.saveAiConfig(id, merged);
      }
    }

    final prompts = json['prompts'];
    if (prompts is Map) {
      for (final entry in prompts.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        try {
          final p = AiPrompts.values.firstWhere((e) => e.name == key);
          if (value.trim().isNotEmpty) {
            prefs.saveAiPrompt(p, value);
          }
        } catch (_) {
          // ignore unknown prompt keys
        }
      }
    }

    final userPrompts = json['userPrompts'];
    if (userPrompts is List) {
      final list = <UserPrompt>[];
      for (final item in userPrompts) {
        if (item is Map<String, dynamic>) {
          list.add(UserPrompt.fromJson(item));
        } else if (item is Map) {
          list.add(UserPrompt.fromJson(item.cast<String, dynamic>()));
        }
      }
      prefs.userPrompts = list;
    }

    final quickPrompts = json['inputQuickPrompts'];
    if (quickPrompts is List) {
      final list = <AiInputQuickPrompt>[];
      for (final item in quickPrompts) {
        if (item is Map<String, dynamic>) {
          list.add(AiInputQuickPrompt.fromJson(item));
        } else if (item is Map) {
          list.add(AiInputQuickPrompt.fromJson(item.cast<String, dynamic>()));
        }
      }
      prefs.aiInputQuickPrompts = list;
    }

    final ui = json['ui'];
    if (ui is Map) {
      final mode = ui['aiPadPanelMode']?.toString();
      if (mode != null) {
        prefs.aiPadPanelMode = AiPadPanelModeEnum.fromCode(mode);
      }
      final side = ui['aiDockSide']?.toString();
      if (side != null) {
        prefs.aiDockSide = AiDockSideEnum.fromCode(side);
      }
      final position = ui['aiPanelPosition']?.toString();
      if (position != null) {
        prefs.aiPanelPosition = AiPanelPositionEnum.fromCode(position);
      }

      final w = (ui['aiPanelWidth'] as num?)?.toDouble();
      if (w != null) prefs.aiPanelWidth = w;
      final h = (ui['aiPanelHeight'] as num?)?.toDouble();
      if (h != null) prefs.aiPanelHeight = h;
      final sheet = (ui['aiSheetInitialSize'] as num?)?.toDouble();
      if (sheet != null) prefs.aiSheetInitialSize = sheet;
      final scale = (ui['aiChatFontScale'] as num?)?.toDouble();
      if (scale != null) prefs.aiChatFontScale = scale;
    }

    final translate = json['translate'];
    if (translate is Map) {
      final providerId = translate['aiTranslateProviderIdV1']?.toString();
      if (providerId != null) {
        prefs.aiTranslateProviderId = providerId;
      }

      final model = translate['aiTranslateModelV1']?.toString();
      if (model != null) {
        prefs.aiTranslateModel = model;
      }

      final concurrency =
          (translate['inlineFullTextTranslateConcurrency'] as num?)?.toInt();
      if (concurrency != null) {
        prefs.inlineFullTextTranslateConcurrency = concurrency;
      }
    }
  } catch (e) {
    AnxLog.severe('ai_settings_sync: failed to apply: $e');
  } finally {
    // Ensure local timestamp matches remote snapshot (Phase 1 semantics).
    if (updatedAt > 0) {
      prefs.aiSettingsUpdatedAt = updatedAt;
    }
  }
}

Map<String, dynamic>? parseAiSettingsJsonString(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (e) {
    AnxLog.info('ai_settings_sync: invalid json: $e');
  }
  return null;
}

String encodeAiSettingsJson(Map<String, dynamic> json) {
  return const JsonEncoder.withIndent('  ').convert(json);
}
