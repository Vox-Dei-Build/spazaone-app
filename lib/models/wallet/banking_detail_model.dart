class BankingDetails {
  final String bankName;
  final String accountHolderName;
  final String accountNumber;
  final String accountType;
  final String branchCode;
  final String reference;

  BankingDetails({
    required this.bankName,
    required this.accountHolderName,
    required this.accountNumber,
    required this.accountType,
    required this.branchCode,
    required this.reference,
  });

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'accountHolderName': accountHolderName,
        'accountNumber': accountNumber,
        'accountType': accountType,
        'branchCode': branchCode,
        'reference': reference,
      };

  factory BankingDetails.fromFirestore(Map<String, dynamic> data) {
    return BankingDetails(
      bankName: data['bankName'] ?? '',
      accountHolderName: data['accountHolderName'] ?? '',
      accountNumber: data['accountNumber'] ?? '',
      accountType: data['accountType'] ?? '',
      branchCode: data['branchCode'] ?? '',
      reference: data['reference'] ?? '',
    );
  }
}
