import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/ledger/widgets/filter_bottom_sheet.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/settings/help/help.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/services/consent_service.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pasella-ui-test-');
    Hive.init(hiveDirectory.path);
    await Hive.openBox(ConsentService.boxName);
    await ConsentService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('typography does not collapse in landscape', (tester) async {
    Future<(double, double)> multipliersFor(Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              SizeConfig().init(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return (SizeConfig.textMultiplier, SizeConfig.imageSizeMultiplier);
    }

    final portrait = await multipliersFor(const Size(390, 844));
    final landscape = await multipliersFor(const Size(844, 390));

    expect(portrait.$1, greaterThanOrEqualTo(7.5));
    expect(landscape.$1, greaterThanOrEqualTo(portrait.$1));
    expect(landscape.$2, portrait.$2);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('custom button exposes semantics and a 48px touch target',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomButton(
            title: 'Save product',
            height: 32,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(CustomButton));
    expect(semantics.label, 'Save product');
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(tester.getSize(find.byType(CustomButton)).height, 48);

    await tester.tap(find.byType(CustomButton));
    expect(tapped, isTrue);
  });

  testWidgets('cancelling filters leaves the applied model unchanged',
      (tester) async {
    final model = AppModel();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: model,
        child: const MaterialApp(
          home: Scaffold(body: FilterBottomSheet()),
        ),
      ),
    );

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(model.reminderDateFilter[0][1], isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(model.reminderDateFilter[0][1], isFalse);
  });

  test('applied filters are deep-copied from temporary state', () {
    final model = AppModel();
    final temporary = [
      ['Today', true],
      ['Pending', false],
      ['Upcoming', false],
    ];

    model.updateFromTemporaryFilters(temporary, 'Name');
    temporary[0][1] = false;

    expect(model.reminderDateFilter[0][1], isTrue);
    expect(model.selectedSortByFilter, 'Name');
  });

  testWidgets('date filter Clear removes the active range', (tester) async {
    var clearCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DateFilterBar(
            selectedDay: DateTime(2026, 7, 10),
            startDate: null,
            endDate: null,
            onDaySelect: (_) {},
            onRangeSelect: (_, __) {},
            onClear: () => clearCalls++,
          ),
        ),
      ),
    );

    expect(
        tester
            .getSize(find.byKey(const ValueKey('workspace-date-filter')))
            .height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.text('Change date'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show all time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all time'));
    await tester.pumpAndSettle();

    expect(clearCalls, 1);
  });

  for (final page in <String, Widget>{
    'Help': const HelpPage(),
    'Privacy': const PrivacyPage(),
  }.entries) {
    testWidgets('${page.key} remains usable at 200% text on a small screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            );
          },
          home: page.value,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });
  }
}
