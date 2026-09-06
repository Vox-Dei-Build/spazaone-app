import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/tutorial_page_body.dart';

void main() {
  testWidgets('support stays reachable below the player in short landscape',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(640, 320), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          appBar: AppBar(title: const Text('Tutorial')),
          body: TutorialPageBody(
            video: const ColoredBox(color: Colors.black),
            onSupport: () => taps++,
          ),
        ),
      ),
    ));
    await tester.ensureVisible(find.text('Talk to support'));
    await tester.tap(find.text('Talk to support'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
