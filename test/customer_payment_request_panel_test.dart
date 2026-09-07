import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/transactions/widgets/customer_payment_request_panel.dart';
import 'package:pasella/services/customer_payment_request_service.dart';
import 'package:pasella/services/repayment_plan_service.dart';
import 'package:pasella/utils/feature_flags.dart';

class _FakeGateway implements CustomerPaymentRequestGateway {
  _FakeGateway(this.overview);

  final CustomerPaymentRequestOverview overview;

  @override
  Future<CustomerPaymentRequestOverview> getOverview({
    required String merchantId,
    required String customerId,
  }) async =>
      overview;

  @override
  Future<CustomerPaymentRequestSendResult> send({
    required String merchantId,
    required String customerId,
    required String quoteKey,
    required String pricingVersion,
    required String idempotencyKey,
  }) async =>
      const CustomerPaymentRequestSendResult(
        requestId: 'cpr_test',
        status: 'queued',
      );

  @override
  Future<CustomerPaymentRequestStatus> getStatus({
    required String requestId,
  }) async =>
      CustomerPaymentRequestStatus(
        requestId: requestId,
        status: 'sent',
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
        cooldownEndsAtMs: DateTime.now()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch,
      );
}

class _FailingGateway implements CustomerPaymentRequestGateway {
  @override
  Future<CustomerPaymentRequestOverview> getOverview({
    required String merchantId,
    required String customerId,
  }) =>
      throw const CustomerPaymentRequestException(
        'Payment requests are temporarily unavailable.',
      );

  @override
  Future<CustomerPaymentRequestStatus> getStatus({required String requestId}) =>
      throw UnimplementedError();

  @override
  Future<CustomerPaymentRequestSendResult> send({
    required String merchantId,
    required String customerId,
    required String quoteKey,
    required String pricingVersion,
    required String idempotencyKey,
  }) =>
      throw UnimplementedError();
}

class _FakeRepaymentPlanGateway implements RepaymentPlanGateway {
  Map<String, Object?>? created;

  @override
  Future<RepaymentPlanCreateResult> create({
    required String merchantId,
    required String customerId,
    required int totalAmountMinor,
    required int installmentAmountMinor,
    required String cadence,
    required int startAtMs,
    required String idempotencyKey,
  }) async {
    created = {
      'merchantId': merchantId,
      'customerId': customerId,
      'totalAmountMinor': totalAmountMinor,
      'installmentAmountMinor': installmentAmountMinor,
      'cadence': cadence,
      'startAtMs': startAtMs,
      'idempotencyKey': idempotencyKey,
    };
    return RepaymentPlanCreateResult(
      planId: 'rp_test',
      totalAmountMinor: totalAmountMinor,
      installmentAmountMinor: installmentAmountMinor,
      cadence: cadence,
      deduped: false,
    );
  }
}

CustomerPaymentRequestOverview _overview({
  bool canRequest = true,
  String reason = 'ready',
  bool online = true,
  int cooldownEndsAtMs = 0,
  CustomerPaymentRequestLastStatus? lastRequest,
}) {
  return CustomerPaymentRequestOverview(
    merchantId: 'merchant',
    customerId: 'customer',
    outstandingAmountMinor: 12345,
    mode: online ? 'whatsapp_online' : 'sms_reminder',
    expectedChannel: online ? 'whatsapp' : 'sms',
    messageCostMinor: 85,
    fallbackMessageCostMinor: 120,
    walletBalanceMinor: 5000,
    walletBalanceAfterMinor: 4915,
    onlinePaymentsReady: online,
    messagePreview:
        'Hi Thandi, your balance at Test Shop is R123,45. You can pay securely here.',
    quoteKey: 'quote',
    pricingVersion: 'pricing-v1',
    canRequest: canRequest,
    reason: reason,
    cooldownEndsAtMs: cooldownEndsAtMs,
    lastRequest: lastRequest,
  );
}

Widget _app({
  required CustomerPaymentRequestOverview overview,
  String? phone = '0821234567',
  VoidCallback? onAddPhone,
  CustomerPaymentRequestGateway? gateway,
  bool isOwing = true,
  double textScale = 1,
  double horizontalPadding = 0,
  RepaymentPlanGateway? repaymentPlanGateway,
}) {
  return MaterialApp(
    theme: kCustomThemeData,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: CustomerPaymentRequestPanel(
          customerId: 'customer',
          customerName: 'Thandi',
          mobileNumber: phone,
          isOwing: isOwing,
          onAddPhone: onAddPhone ?? () {},
          onSetUpOnlinePayments: () {},
          merchantId: 'merchant',
          service: gateway ?? _FakeGateway(overview),
          repaymentPlanService: repaymentPlanGateway,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('SpazaSans')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await fonts.load();
  });
  setUp(() => FeatureFlags.enableCustomerPaymentRequests = true);
  tearDown(() => FeatureFlags.enableCustomerPaymentRequests = false);

  testWidgets('shows one prominent request action and exact receipt details',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(overview: _overview()));
    await tester.pumpAndSettle();

    expect(find.text('Request payment'), findsOneWidget);
    await tester.tap(find.text('Request payment'));
    await tester.pumpAndSettle();

    expect(find.text('Send payment request?'), findsOneWidget);
    expect(find.text('R123,45'), findsOneWidget);
    expect(find.text('R0,85'), findsOneWidget);
    expect(find.text('R49,15'), findsOneWidget);
    expect(find.text('R1,20 by SMS'), findsOneWidget);
    expect(find.text('Send request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes a missing phone to customer editing', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _app(
        overview: _overview(canRequest: false, reason: 'phone_missing'),
        phone: '',
        onAddPhone: () => opened = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add customer phone number'));
    expect(opened, isTrue);
  });

  testWidgets('enforces the visible cooldown state', (tester) async {
    final cooldown =
        DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
    await tester.pumpWidget(
      _app(
        overview: _overview(
          canRequest: false,
          reason: 'cooldown_active',
          cooldownEndsAtMs: cooldown,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('You can send another request'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('customer-request-payment-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('keeps payment actions and last-request status compact',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        horizontalPadding: 16,
        overview: _overview(
          lastRequest: CustomerPaymentRequestLastStatus(
            requestId: 'request-1',
            status: 'sent',
            sentAtMs: DateTime.now()
                .subtract(const Duration(hours: 3))
                .millisecondsSinceEpoch,
            cooldownEndsAtMs: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final request = find.byKey(const Key('customer-request-payment-button'));
    final plan = find.byKey(const Key('customer-create-repayment-plan-button'));
    expect(tester.getCenter(request).dy, tester.getCenter(plan).dy);
    expect(find.text('Last request sent 3 hours ago.'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CustomerPaymentRequestPanel)).height,
      lessThanOrEqualTo(80),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks both payment actions when large text needs more room',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        overview: _overview(),
        horizontalPadding: 16,
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();

    final request = find.byKey(const Key('customer-request-payment-button'));
    final plan = find.byKey(const Key('customer-create-repayment-plan-button'));
    expect(
        tester.getRect(plan).top, greaterThan(tester.getRect(request).bottom));
    expect(find.text('Request payment'), findsOneWidget);
    expect(find.text('Set plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides payment requests when the account is settled',
      (tester) async {
    await tester.pumpWidget(_app(overview: _overview(), isOwing: false));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('customer-request-payment-button')), findsNothing);
  });

  testWidgets('shows a safe retry after an overview failure', (tester) async {
    await tester.pumpWidget(
      _app(overview: _overview(), gateway: _FailingGateway()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('Payment requests are temporarily unavailable.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmation remains scrollable at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(overview: _overview(), textScale: 1.6));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request payment'));
    await tester.pumpAndSettle();
    expect(find.text('Send request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a repayment plan from the customer account',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plans = _FakeRepaymentPlanGateway();
    await tester.pumpWidget(
      _app(overview: _overview(), repaymentPlanGateway: plans),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('customer-create-repayment-plan-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('repayment-plan-installment')),
      '25',
    );
    await tester.tap(find.byKey(const Key('repayment-plan-create')));
    await tester.pumpAndSettle();

    expect(plans.created?['merchantId'], 'merchant');
    expect(plans.created?['customerId'], 'customer');
    expect(plans.created?['totalAmountMinor'], 12345);
    expect(plans.created?['installmentAmountMinor'], 2500);
    expect(plans.created?['cadence'], 'weekly');
    expect(find.textContaining('Repayment plan created'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
