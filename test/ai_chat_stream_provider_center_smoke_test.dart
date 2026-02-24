import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AiChatStream uses Provider Center selected provider',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    const providerId = 'test-provider-id';

    final providers = [
      AiProviderMeta(
        id: 'openai',
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: 1,
        updatedAt: 1,
        logoKey: 'assets/images/openai.png',
      ),
      AiProviderMeta(
        id: providerId,
        name: 'My Gateway',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'selectedAiService': providerId,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_$providerId': jsonEncode({
        'url': 'https://example.com/v1/chat/completions',
        'api_key': 'TEST_KEY',
        'model': 'my-model',
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

    // Let the first frame/layout complete.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('My Gateway'), findsOneWidget);
    expect(find.textContaining('my-model'), findsOneWidget);

    // Edit model via in-chat dialog.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'new-model');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('new-model'), findsOneWidget);
  });
}
