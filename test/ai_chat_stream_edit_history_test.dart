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
  testWidgets('AiChatStream can edit a user message and confirm regenerate',
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
      ),
    ];

    // Intentionally leave aiConfig_openai empty so regenerate will not hit
    // network and will immediately yield "AI service not configured".
    SharedPreferences.setMockInitialValues({
      'selectedAiService': providerId,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_$providerId': jsonEncode({}),
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

    // Ensure the async provider build() has completed before mutating state.
    await container.read(aiChatProvider.future);

    container.read(aiChatProvider.notifier).restore([
      ChatMessage.humanText('Old question'),
      ChatMessage.ai('Old answer'),
    ]);

    await tester.pump(const Duration(milliseconds: 50));

    // Tap Edit on the user bubble.
    await tester.tap(find.text('编辑'));
    await tester.pump(const Duration(milliseconds: 200));

    // Edit dialog (avoid matching the main chat input TextField).
    final dialogTextField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogTextField, 'New question');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('保存'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Confirm dialog.
    expect(find.text('从这里重新生成？'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('确认'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));

    final l10n = L10n.of(tester.element(find.byType(AiChatStream)));
    final state = container.read(aiChatProvider).value;
    expect(state, isNotNull);

    // User text should be replaced (state-level assertion; UI uses SelectableText).
    expect(state!.first is HumanChatMessage, isTrue);
    expect(state.first.contentAsString, equals('New question'));

    // And regenerate stream should produce a (non-network) assistant response.
    expect(state.last is AIChatMessage, isTrue);
    expect(state.last.contentAsString, contains(l10n.aiServiceNotConfigured));
  });
}
