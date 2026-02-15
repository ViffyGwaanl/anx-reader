import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AiProviderCenterPage builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AiProviderCenterPage(),
      ),
    );
    expect(find.text('供应商中心'), findsOneWidget);
  });
}
