import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';

void main() {
  test('only explicit save choices may commit a transaction', () {
    expect(CostSheetOutcome.send.shouldCommit, isTrue);
    expect(CostSheetOutcome.skip.shouldCommit, isTrue);
    expect(CostSheetOutcome.keepEditing.shouldCommit, isFalse);
    expect(CostSheetOutcome.discard.shouldCommit, isFalse);
    expect(CostSheetOutcome.dismissed.shouldCommit, isFalse);
  });

  testWidgets('closing confirmation can return to editing without saving',
      (tester) async {
    CostSheetOutcome? outcome;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                outcome =
                    await CostConfirmationSheet.confirmDiscardOrKeep(context);
              },
              child: const Text('Close confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Close confirmation'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this transaction?'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(outcome, CostSheetOutcome.keepEditing);
    expect(outcome!.shouldCommit, isFalse);
  });

  testWidgets('discarding confirmation returns a non-committing outcome',
      (tester) async {
    CostSheetOutcome? outcome;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                outcome =
                    await CostConfirmationSheet.confirmDiscardOrKeep(context);
              },
              child: const Text('Close confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Close confirmation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(outcome, CostSheetOutcome.discard);
    expect(outcome!.shouldCommit, isFalse);
    expect(outcome!.shouldDiscard, isTrue);
  });
}
