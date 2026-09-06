import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/settings/settings.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => FeatureFlags.multiStoreOperatorsEnabled.value = true);

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

    expect(find.text('Shop setup'), findsOneWidget);
    expect(find.text('Checklist and WhatsApp ordering link'), findsOneWidget);
    expect(find.text('WhatsApp Ordering Link'), findsNothing);
  });

  testWidgets('settings business name opens its existing route',
      (tester) async {
    FeatureFlags.multiStoreOperatorsEnabled.value = false;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: const SettingsPage(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Text('Opened ${settings.name}')),
      ),
    ));
    await tester.tap(find.text('Business name'));
    await tester.pumpAndSettle();
    expect(find.text('Opened ${BusinessNamePage.id}'), findsOneWidget);
  });

  testWidgets(
      'approachable settings retains every destination at 320px and 200% text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <SettingsDestination>[];
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: SettingsMenu(onSelected: selected.add)),
    ));

    for (final destination in SettingsDestination.values) {
      final row = find.byKey(ValueKey('settings-${destination.name}'));
      await tester.scrollUntilVisible(row, 200);
      final tile = find.descendant(of: row, matching: find.byType(ListTile));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
      await tester.tap(tile);
      expect(selected.last, destination);
      expect(tester.takeException(), isNull);
    }
    expect(selected, SettingsDestination.values);
  });

  testWidgets('settings rows share fixed-size text and icons across screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(
        body: SettingTile(
          title: 'Privacy',
          subTitle: 'Analytics and crash reports',
          icon: Icons.shield_outlined,
          onTap: () {},
        ),
      ),
    ));
    expect(tester.widget<Text>(find.text('Privacy')).style?.fontSize, 16);
    expect(
      tester
          .widget<Text>(find.text('Analytics and crash reports'))
          .style
          ?.fontSize,
      13,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.shield_outlined)).size, 22);
    expect(
        tester.getSize(find.byType(ListTile)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
