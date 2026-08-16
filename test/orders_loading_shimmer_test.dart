import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_skeleton.dart';

void main() {
  testWidgets('order rows use shimmer without a spinner', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderSkeleton(
            key: ValueKey('order-loading-shimmer'),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('order-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
