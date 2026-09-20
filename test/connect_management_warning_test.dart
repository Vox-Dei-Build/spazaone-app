import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/contact/connect/connect_manangement.dart';

void main() {
  testWidgets('conversation warning exposes a visible retry action',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHistoryWarningBanner(
            warning: 'Some bot messages could not be displayed.',
            onRetry: () async => retries++,
          ),
        ),
      ),
    );

    expect(
        find.text('Some bot messages could not be displayed.'), findsOneWidget);
    final retry = find.byKey(const Key('customer-message-history-retry'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(retries, 1);
  });
}
