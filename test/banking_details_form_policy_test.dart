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

  test('banking form catalogue is available without a network call', () async {
    final banks = await PaymentSetupService.supportedSettlementBanks();

    expect(banks, hasLength(17));
    expect(
      banks.singleWhere((bank) => bank.name == 'FNB').branchCode,
      '250655',
    );
    expect(
      banks.singleWhere((bank) => bank.name == 'Capitec').supportedAccountTypes,
      ['personal'],
    );
    expect(
      banks.every((bank) => RegExp(r'^\d{6}$').hasMatch(bank.branchCode)),
      isTrue,
    );
  });
}
