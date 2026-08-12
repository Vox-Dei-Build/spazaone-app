import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/top_up_tab.dart';

void main() {
  testWidgets('Top Up matches the compact Account dashboard presentation', (
    tester,
  ) async {
    var onlineTaps = 0;
    var helpTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: BillingTopUpMenu(
              showOnline: true,
              showHelp: true,
              onOnline: () => onlineTaps++,
              onHelp: () => helpTaps++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pay online'), findsOneWidget);
    expect(find.text('Top up on WhatsApp'), findsNothing);
    expect(find.text('How top-ups work'), findsOneWidget);
    expect(find.textContaining('campaign credits'), findsNothing);
    expect(find.textContaining('linked stores'), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);

    final dashboard = tester.getRect(
      find.byKey(const ValueKey('billing-top-up-dashboard')),
    );
    final lastTile = tester.getRect(
      find.byKey(const ValueKey('billing-top-up-help')),
    );
    expect(lastTile.bottom, greaterThan(dashboard.bottom - 20));
    expect(lastTile.height, greaterThan(90));

    await tester.tap(find.text('Pay online'));
    await tester.tap(find.text('How top-ups work'));
    expect(onlineTaps, 1);
    expect(helpTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Top Up hides unavailable optional actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: BillingTopUpMenu(
              showOnline: false,
              showHelp: false,
              onOnline: () {},
              onHelp: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pay online'), findsNothing);
    expect(find.text('How top-ups work'), findsNothing);
    expect(find.text('Top up on WhatsApp'), findsNothing);
    expect(
      find.textContaining('No manual WhatsApp top-up is required'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
