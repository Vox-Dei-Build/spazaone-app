import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';

void main() {
  test('tutorial URL parser rejects values WebView cannot load', () {
    for (final value in [
      '',
      '   ',
      '/relative/tutorial',
      'javascript:alert(1)',
      'data:text/html,hello',
    ]) {
      expect(
        LoomVideoPage.parseVideoUri(value),
        isNull,
        reason: 'Expected "$value" to be rejected',
      );
    }
  });

  test('tutorial URL parser accepts secure URLs and repairs a missing scheme',
      () {
    expect(
      LoomVideoPage.parseVideoUri('https://www.loom.com/share/abc'),
      Uri.parse('https://www.loom.com/share/abc'),
    );
    expect(
      LoomVideoPage.parseVideoUri('www.loom.com/share/abc'),
      Uri.parse('https://www.loom.com/share/abc'),
    );
  });

  testWidgets('missing tutorial URL shows a safe fallback instead of throwing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoomVideoPage(
          loomUrl: '',
          title: 'How to record sales',
        ),
      ),
    );

    expect(find.text('How to record sales'), findsOneWidget);
    expect(find.byKey(const Key('tutorial-video-unavailable')), findsOneWidget);
    expect(
      find.text('This tutorial is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Talk to support'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
