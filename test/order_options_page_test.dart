import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/settings/order_options/order_options_page.dart';
import 'package:pasella/services/merchant_ordering_options_service.dart';

void main() {
  testWidgets(
      'failed initial load requires a retry before options can be saved',
      (tester) async {
    var loads = 0;
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: OrderOptionsPage(
        loader: () async {
          if (++loads == 1) throw StateError('offline');
          return const MerchantOrderingOptions(
            configured: true,
            payLaterEnabled: true,
            deliveryEnabled: false,
            deliveryFlatFeeMinor: 1500,
            deliveryServiceAreaText: 'Town centre',
          );
        },
        saver: ({
          required payLaterEnabled,
          required deliveryEnabled,
          required deliveryFlatFeeMinor,
          required deliveryServiceAreaText,
        }) async {
          saves++;
          return const MerchantOrderingOptions.defaults();
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('order-options-load-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-order-options')), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(saves, 0);

    await tester.tap(find.byKey(const ValueKey('retry-order-options')));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(
        find.byKey(const ValueKey('order-options-load-error')), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('pay-later-option')),
          )
          .value,
      isTrue,
    );
    expect(find.byKey(const ValueKey('save-order-options')), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('failed save preserves edits and explains that saving failed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderOptionsPage(
        loader: () async => const MerchantOrderingOptions.defaults(),
        saver: ({
          required payLaterEnabled,
          required deliveryEnabled,
          required deliveryFlatFeeMinor,
          required deliveryServiceAreaText,
        }) async =>
            throw StateError('offline'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay-later-option')));
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('save-order-options')));
    await tester.tap(find.byKey(const ValueKey('save-order-options')));
    await tester.pumpAndSettle();
    expect(find.text('Order options could not be saved. Please try again.'),
        findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('pay-later-option')),
          )
          .value,
      isTrue,
    );
    expect(find.byKey(const ValueKey('retry-order-options')), findsNothing);
  });

  testWidgets('defaults keep delivery and Pay Later off', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderOptionsPage(
          loader: () async => const MerchantOrderingOptions.defaults(),
          saver: ({
            required payLaterEnabled,
            required deliveryEnabled,
            required deliveryFlatFeeMinor,
            required deliveryServiceAreaText,
          }) async =>
              const MerchantOrderingOptions.defaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pickup'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('pay-later-option')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('delivery-option')),
          )
          .value,
      isFalse,
    );

    final pickup = tester.getRect(
      find.byKey(const ValueKey('pickup-option-card')),
    );
    final payLater = tester.getRect(
      find.byKey(const ValueKey('pay-later-option-card')),
    );
    final delivery = tester.getRect(
      find.byKey(const ValueKey('delivery-option-card')),
    );
    expect(payLater.top - pickup.bottom, 12);
    expect(delivery.top - payLater.bottom, 12);
  });

  testWidgets('saves delivery fee, service area and Pay Later', (tester) async {
    bool? savedPayLater;
    bool? savedDelivery;
    int? savedFee;
    String? savedArea;
    await tester.pumpWidget(
      MaterialApp(
        home: OrderOptionsPage(
          loader: () async => const MerchantOrderingOptions.defaults(),
          saver: ({
            required payLaterEnabled,
            required deliveryEnabled,
            required deliveryFlatFeeMinor,
            required deliveryServiceAreaText,
          }) async {
            savedPayLater = payLaterEnabled;
            savedDelivery = deliveryEnabled;
            savedFee = deliveryFlatFeeMinor;
            savedArea = deliveryServiceAreaText;
            return const MerchantOrderingOptions(
              configured: true,
              payLaterEnabled: true,
              deliveryEnabled: true,
              deliveryFlatFeeMinor: 1250,
              deliveryServiceAreaText: 'Within 5 km',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pay-later-option')));
    await tester.tap(find.byKey(const ValueKey('delivery-option')));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('delivery-fee-field')),
      '12.50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('service-area-field')),
      'Within 5 km',
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('save-order-options')));
    await tester.tap(find.byKey(const ValueKey('save-order-options')));
    await tester.pumpAndSettle();

    expect(savedPayLater, isTrue);
    expect(savedDelivery, isTrue);
    expect(savedFee, 1250);
    expect(savedArea, 'Within 5 km');
    expect(find.text('Order options saved.'), findsOneWidget);
  });
}
