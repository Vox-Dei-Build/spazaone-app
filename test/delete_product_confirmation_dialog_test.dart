import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/product_details/widgets/delete_product_confirmation_dialog.dart';

void main() {
  test('authorized deletion or discard can exit a dirty form', () {
    expect(
      productDetailsCanPop(
        hasUnsavedChanges: true,
        exitAuthorized: true,
      ),
      isTrue,
    );
  });

  testWidgets('delete dialog returns confirmation to the owning page', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const DeleteConfirmationDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(DeleteConfirmationDialog), findsNothing);
  });
}
