import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AiChatStream shows assistant variants with left/right switcher',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    const providerId = 'openai';

    final providers = [
      AiProviderMeta(
        id: providerId,
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: 1,
        updatedAt: 1,
        logoKey: 'assets/images/openai.png',
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'selectedAiService': providerId,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_$providerId': jsonEncode({
        'url': 'https://example.com/v1/chat/completions',
        'api_key': 'TEST_KEY',
        'model': 'test-model',
      }),
    });

    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const AiChatStream(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream)),
    );

    container.read(aiChatProvider.notifier).restore([
      ChatMessage.humanText('Q'),
      ChatMessage.ai('A1'),
      ChatMessage.ai('A2'),
    ]);

    await tester.pump(const Duration(milliseconds: 50));

    // Default: show the latest variant.
    expect(find.textContaining('A2'), findsOneWidget);
    expect(find.textContaining('A1'), findsNothing);

    // Switcher shows 2/2.
    expect(find.text('2/2'), findsOneWidget);

    // Tap left to view the previous variant.
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('A1'), findsOneWidget);
    expect(find.textContaining('A2'), findsNothing);
    expect(find.text('1/2'), findsOneWidget);
  });
}
