import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/sales/widgets/combined_online_orders.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';
import 'package:pasella/shared/widgets/workspace_date_filter.dart';

const _screenSize = Size(320, 568);
const _navigationInset = 48.0;

Widget _host(Widget child, double keyboardInset,
        {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          padding: EdgeInsets.only(
              bottom: keyboardInset == 0 ? _navigationInset : 0),
          viewPadding: const EdgeInsets.only(bottom: _navigationInset),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Future<void> _expectLastActionVisible(
  WidgetTester tester, {
  required String scrollKey,
  required Finder action,
  required double keyboardInset,
}) async {
  final drawer = find.byKey(ValueKey(scrollKey));
  await tester.scrollUntilVisible(action, 120,
      scrollable: find.descendant(
        of: drawer,
        matching: find.byType(Scrollable),
      ));
  await tester.drag(drawer, const Offset(0, -600));
  await tester.pumpAndSettle();
  final visibleBottom = _screenSize.height -
      (keyboardInset == 0 ? _navigationInset : keyboardInset);
  expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(visibleBottom));
  expect(tester.getBottomRight(drawer).dy, lessThanOrEqualTo(visibleBottom));
  expect(action.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final keyboardInset in [0.0, 240.0]) {
    testWidgets('date drawer clears bottom insets ($keyboardInset)',
        (tester) async {
      tester.view.physicalSize = _screenSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var cleared = false;
      await tester.pumpWidget(_host(
        WorkspaceDateFilter(
          selectedDay: DateTime(2026, 9, 4),
          startDate: null,
          endDate: null,
          onDaySelect: (_) {},
          onRangeSelect: (_, __) {},
          onClear: () => cleared = true,
        ),
        keyboardInset,
      ));
      await tester.tap(find.byKey(const ValueKey('workspace-date-filter')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final action = find.widgetWithText(ListTile, 'Show all time');
      await _expectLastActionVisible(tester,
          scrollKey: 'workspace-date-choices-scroll',
          action: action,
          keyboardInset: keyboardInset);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(find.text('Choose dates'), findsNothing);
    });

    testWidgets('invoice drawer keeps PDF choice reachable ($keyboardInset)',
        (tester) async {
      tester.view.physicalSize = _screenSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      Future<File?>? picked;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => picked =
                StockInvoiceAttachmentService().pickAndPrepare(context),
            child: const Text('Attach invoice'),
          ),
        ),
        keyboardInset,
        navigatorKey: navigator,
      ));
      await tester.tap(find.text('Attach invoice'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _expectLastActionVisible(tester,
          scrollKey: 'stock-invoice-source-scroll',
          action: find.widgetWithText(ListTile, 'PDF from Files'),
          keyboardInset: keyboardInset);
      // Dismissing the chooser does not open a device picker or attach a file.
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(await picked, isNull);
    });

    testWidgets('online order filters keep apply reachable ($keyboardInset)',
        (tester) async {
      tester.view.physicalSize = _screenSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var cleared = false;
      await tester.pumpWidget(_host(
        CombinedOnlineOrders(
          selectedDay: null,
          startDate: null,
          endDate: null,
          onDaySelect: (_) {},
          onRangeSelect: (_, __) {},
          onClearDates: () => cleared = true,
          onSetup: () {},
          onShareShop: () {},
          ownedLoader: ({selectedDay, startDate, endDate}) async => [],
          supplierStream: () => Stream.value([]),
        ),
        keyboardInset,
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Source and date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source and date'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final action = find.widgetWithText(FilledButton, 'Show orders');
      await _expectLastActionVisible(tester,
          scrollKey: 'online-order-filters-scroll',
          action: action,
          keyboardInset: keyboardInset);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(find.text('More order filters'), findsNothing);
    });
  }
}
