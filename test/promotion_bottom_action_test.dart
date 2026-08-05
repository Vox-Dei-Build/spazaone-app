import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_bottom_action.dart';

void main() {
  testWidgets('promotion action clears the system navigation inset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 720),
            padding: EdgeInsets.only(bottom: 32),
            viewPadding: EdgeInsets.only(bottom: 32),
          ),
          child: Scaffold(
            bottomNavigationBar: PromotionBottomAction(
              child: SizedBox(
                key: const Key('review-action'),
                height: 48,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Review promotion'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final actionBottom = tester
        .getBottomRight(
          find.byKey(const Key('review-action')),
        )
        .dy;
    expect(actionBottom, lessThanOrEqualTo(720 - 32));
  });

  testWidgets('scaffold keeps promotion action above the keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 720),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            bottomNavigationBar: PromotionBottomAction(
              child: SizedBox(
                key: const Key('continue-action'),
                height: 48,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final actionBottom = tester
        .getBottomRight(
          find.byKey(const Key('continue-action')),
        )
        .dy;
    expect(actionBottom, lessThanOrEqualTo(720 - 280));
  });
}
