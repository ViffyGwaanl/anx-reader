import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:flutter/material.dart';

class AiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.ai;

  @override
  String getLabel(BuildContext context) => L10n.of(context).navBarAI;

  /// AI translation uses native language names (e.g., "简体中文", "English")
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
    final prompt = generatePromptTranslate(
      text,
      mapLanguageCode(to),
      mapLanguageCode(from),
      contextText: contextText,
    );

    final providerId = Prefs().aiTranslateProviderIdEffective;
    final model = Prefs().aiTranslateModel.trim();

    return AiStream(
      prompt: prompt,
      regenerate: true,
      identifier: providerId.isEmpty ? null : providerId,
      config: model.isEmpty ? null : {'model': model},
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
      final payload = generatePromptTranslate(
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
