import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/pages/ledger/widgets/shop_link_action.dart';

void main() {
  testWidgets('shop link action is visible, accessible, and tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ShopLinkAction(onPressed: () => taps++),
          ),
        ),
      ),
    );

    expect(find.text('Shop link'), findsOneWidget);
    expect(find.byType(FaIcon), findsOneWidget);
    expect(
      tester.widget<FaIcon>(find.byType(FaIcon)).icon,
      FontAwesomeIcons.whatsapp,
    );
    expect(
      find.bySemanticsLabel('Open your WhatsApp ordering link'),
      findsOneWidget,
    );
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Open your WhatsApp ordering link'),
    );
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Shop link'));
    expect(taps, 1);
  });
}
