import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/shared/widgets/channel_capability_badge.dart';

void main() {
  testWidgets('customer row shows channel capability without a text pill', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionTile(
            color: kTertiaryColor.toARGB32(),
            name: 'Naledi Mokoena',
            amount: 120,
            remarks: 'Groceries',
            status: 'DUE',
            type: 'Credit',
            date: '5 Aug',
            selectedCustomerId: 'customer-1',
            balance: -120,
            number: '0648370009',
            unreadCount: 0,
            showChannelCapability: true,
            hasWhatsApp: true,
          ),
        ),
      ),
    );

    final badge = tester.widget<ChannelCapabilityBadge>(
      find.byType(ChannelCapabilityBadge),
    );
    expect(badge.compact, isTrue);
    expect(
      find.bySemanticsLabel(RegExp('WhatsApp available')),
      findsOneWidget,
    );
    expect(find.text('WhatsApp'), findsNothing);
    expect(
      find.byTooltip('Reachable on WhatsApp — reminders will use WhatsApp.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('compact channel indicators label every phone state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              ChannelCapabilityBadge(
                hasNumber: true,
                hasWhatsApp: true,
                compact: true,
                iconSize: 12,
              ),
              ChannelCapabilityBadge(
                hasNumber: true,
                hasWhatsApp: false,
                compact: true,
                iconSize: 12,
              ),
              ChannelCapabilityBadge(
                hasNumber: true,
                hasWhatsApp: null,
                compact: true,
                iconSize: 12,
              ),
              ChannelCapabilityBadge(
                hasNumber: false,
                hasWhatsApp: null,
                compact: true,
                iconSize: 12,
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in [
      'WhatsApp available',
      'SMS available',
      'Phone number available',
      'No phone number',
    ]) {
      expect(find.bySemanticsLabel(RegExp(label)), findsOneWidget);
    }
    expect(
      find.byTooltip('Not on WhatsApp — reminders will be sent via SMS.'),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        'WhatsApp status not yet checked. Spaza One tries WhatsApp first and '
        'falls back to SMS automatically.',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('No phone number on file — add one to send reminders.'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('customer summary is compact and follow-up rows are tappable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final report = Report(
      totalNumberofNPAs: 1,
      customersWithNPAs: const [
        {
          'id': 'customer-1',
          'name': 'A Customer With A Very Long Name',
          'number': '0648370009',
          'balance': -1234.50,
          'profileImageUrl': null,
        },
      ],
      nplRatio: 25,
      cashflowImpact: -1234.50,
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerBalanceSummary(
              report: report,
              totalCustomers: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer balance summary'), findsNothing);
    expect(find.text('Outstanding balance'), findsOneWidget);
    expect(find.text('Customers to follow up'), findsOneWidget);
    expect(find.text('A Customer With A Very Long Name'), findsOneWidget);
    expect(find.text('+27648370009'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('customer-follow-up-customer-1')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.visibility), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
