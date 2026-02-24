import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AiProviderCenterPage builds', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'CN'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiProviderCenterPage(),
      ),
    );

    // Let the FutureBuilder complete (Prefs.initPrefs + initial frame).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('供应商中心').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('供应商中心'), findsOneWidget);
  });
}
