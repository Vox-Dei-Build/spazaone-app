import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('banking values are selectable and Copy all is complete', (
    tester,
  ) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BankingDetailsSummary(
            bankName: 'Village Bank',
            accountHolderName: 'Nomsa Store',
            accountNumber: '1234567890',
            accountType: 'Business',
            branchCode: '470010',
            reference: 'Nomsa',
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsNWidgets(6));
    await tester.tap(find.byKey(const ValueKey('copy-all-banking-details')));
    await tester.pump();

    expect(copiedText, contains('Bank: Village Bank'));
    expect(copiedText, contains('Account Number: 1234567890'));
    expect(copiedText, contains('Branch Code: 470010'));
    expect(copiedText, contains('Reference: Nomsa'));
    expect(find.text('Banking details copied'), findsOneWidget);
  });
}
