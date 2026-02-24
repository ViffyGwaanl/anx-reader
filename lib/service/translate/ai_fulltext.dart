import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:flutter/material.dart';

/// AI provider for *inline full-text translation*.
///
/// Key difference vs [AiTranslateProvider]:
/// - Uses a dedicated prompt that MUST output translation-only text.
class AiFullTextTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.aiFullText;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsTranslateAiFulltext;

  /// Full-text translation uses native language names (e.g., "简体中文", "English")
  /// instead of ISO codes for better prompt understanding.
  @override
  String mapLanguageCode(LangListEnum lang) => lang.nativeName;

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
  }) {
    // Full-text translation should be used via translateTextOnly (WebView handler).
    // We still provide a basic streaming widget for testing.
    final payload = generatePromptTranslateFulltext(
      text,
      mapLanguageCode(to),
      mapLanguageCode(from),
      contextText: contextText,
    );

    final messages = payload.buildMessages();

    final providerId = Prefs().aiTranslateProviderIdEffective;
    final model = Prefs().aiTranslateModel.trim();

    return StreamBuilder<String>(
      stream: aiGenerateStream(
        messages,
        identifier: providerId.isEmpty ? null : providerId,
        config: model.isEmpty ? null : {'model': model},
        regenerate: false,
      ),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return const Text('...');
        }
        return Text(data);
      },
    );
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
  }) async* {
    try {
      final payload = generatePromptTranslateFulltext(
        text,
        mapLanguageCode(to),
        mapLanguageCode(from),
        contextText: contextText,
      );

      final messages = payload.buildMessages();

      final providerId = Prefs().aiTranslateProviderIdEffective;
      final model = Prefs().aiTranslateModel.trim();

      await for (final result in aiGenerateStream(
        messages,
        identifier: providerId.isEmpty ? null : providerId,
        config: model.isEmpty ? null : {'model': model},
        regenerate: false,
      )) {
        yield result;
      }
    } catch (e) {
      yield L10n.of(navigatorKey.currentContext!).translateError + e.toString();
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: 'Tip',
        type: ConfigItemType.tip,
        defaultValue:
            L10n.of(navigatorKey.currentContext!).settingsTranslateAiTip,
      ),
    ];
  }
}
