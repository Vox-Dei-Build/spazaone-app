import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/store_session.dart';

void main() {
  test('shared membership resolves the canonical campaign wallet', () {
    final membership = StoreMembership.fromMap({
      'storeId': 'store-secondary',
      'storeName': 'Second Store',
      'role': 'operator',
      'sharedCampaignCredits': true,
      'campaignWalletStoreId': 'owner-primary',
    });

    expect(membership.sharedCampaignCredits, isTrue);
    expect(membership.resolvedCampaignWalletStoreId, 'owner-primary');
    expect(membership.role, StoreRole.operator);
  });

  test('legacy membership keeps its own wallet path', () {
    final membership = StoreMembership.fromMap({
      'storeId': 'legacy-owner',
      'storeName': 'Legacy Store',
      'role': 'owner',
    });

    expect(membership.sharedCampaignCredits, isFalse);
    expect(membership.resolvedCampaignWalletStoreId, 'legacy-owner');
  });

  test('missing shared wallet pointer fails back to the selected store', () {
    final membership = StoreMembership.fromMap({
      'storeId': 'store-a',
      'storeName': 'Store A',
      'role': 'admin',
      'sharedCampaignCredits': true,
      'campaignWalletStoreId': '  ',
    });

    expect(membership.resolvedCampaignWalletStoreId, 'store-a');
  });
}
