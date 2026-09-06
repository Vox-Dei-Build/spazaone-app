import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/pages/wallet/view_model/banking_details_persistence.dart';

BankingDetails _details(String holder) => BankingDetails(
      bankName: 'Example Bank',
      accountHolderName: holder,
      accountNumber: '0000000000',
      accountType: 'Business',
      branchCode: '000000',
      reference: 'Example',
    );

void main() {
  test('a new account retains its ID and the second save updates that account',
      () async {
    final stored = <String, BankingDetails>{};
    var creates = 0;
    Future<String> create(BankingDetails details) async {
      creates++;
      stored['saved-account'] = details;
      return 'saved-account';
    }

    Future<void> update(String id, BankingDetails details) async {
      expect(stored.containsKey(id), isTrue);
      stored[id] = details;
    }

    var id = await persistBankingDetails(
      details: _details('Original shop'),
      documentId: null,
      create: create,
      update: update,
    );
    id = await persistBankingDetails(
      details: _details('Updated shop'),
      documentId: id,
      create: create,
      update: update,
    );
    expect(id, 'saved-account');
    expect(creates, 1);
    expect(stored, hasLength(1));
    expect(stored[id]!.accountHolderName, 'Updated shop');
  });

  test('an existing saved document is updated without creating another account',
      () async {
    final value = _details('Updated shop');
    String? updatedId;
    final id = await persistBankingDetails(
      details: value,
      documentId: 'existing-account',
      create: (_) async => fail('Existing account must be updated'),
      update: (id, details) async {
        updatedId = id;
        expect(details, same(value));
      },
    );
    expect(id, 'existing-account');
    expect(updatedId, 'existing-account');
  });

  test('a failed update is not replaced with a new account', () async {
    await expectLater(
      persistBankingDetails(
        details: _details('Updated shop'),
        documentId: 'existing-account',
        create: (_) async => fail('Failed update must not create a duplicate'),
        update: (_, __) async => throw StateError('offline'),
      ),
      throwsStateError,
    );
  });
}
