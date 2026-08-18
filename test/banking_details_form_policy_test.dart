import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/services/payment_setup_service.dart';

void main() {
  test('only provider-supported account types map to constrained choices', () {
    expect(canonicalSettlementAccountType('Personal'), 'personal');
    expect(canonicalSettlementAccountType('Business'), 'business');
    expect(canonicalSettlementAccountType('Savings'), isNull);
  });

  test('supported bank projection keeps the provider branch code', () {
    final bank = SupportedSettlementBank.fromMap(const {
      'name': 'Example Bank',
      'branchCode': '632005',
      'supportedAccountTypes': ['personal', 'business'],
    });
    expect(bank.name, 'Example Bank');
    expect(bank.branchCode, '632005');
    expect(bank.supportedAccountTypes, ['personal', 'business']);
  });
}
