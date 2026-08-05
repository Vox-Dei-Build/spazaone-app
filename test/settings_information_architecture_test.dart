import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/settings/settings.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => FeatureFlags.multiStoreOperatorsEnabled.value = false);

  Future<void> pumpSettings(WidgetTester tester) {
    return tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppModel(),
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
  }

  testWidgets('settings keeps setup and ordering link in one destination', (
    tester,
  ) async {
    FeatureFlags.multiStoreOperatorsEnabled.value = false;
    await pumpSettings(tester);

    expect(find.text('Shop Setup'), findsOneWidget);
    expect(find.text('Checklist and WhatsApp ordering link'), findsOneWidget);
    expect(find.text('WhatsApp Ordering Link'), findsNothing);
  });
}
