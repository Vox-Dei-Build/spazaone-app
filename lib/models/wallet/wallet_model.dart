final Map<String, List<String>> serviceBanks = {
  'Flash': ['FNB', 'ABSA', 'Nedbank'],
  'HelloPaisa': ['FNB', 'Nedbank', 'Standard Bank'],
};

final Map<String, Map<String, String>> predefinedAccountDetails = {
  'Flash': {
    'FNB': '62544397492', // Add Flash FNB account number
    'ABSA': '4072416316', // Add Flash ABSA account number
    'Nedbank': '1195253826', // Add Flash Nedbank account number if available
    'AccountName': 'FLASH mobile vending (PTY) LTD'
  },
  'HelloPaisa': {
    'FNB': '62508532141', // Add HelloPaisa FNB account number if available
    'Nedbank':
        '1137266708', // Add HelloPaisa Nedbank account number if available
    'Standard Bank':
        '12250252', // Add HelloPaisa Standard Bank account number if available
    'AccountName': 'Hello Paisa Pty Ltd'
  },
};

final List<String> services = [
  'Select Service',
  'Absa',
  'Capitec',
  'Flash',
  'FNB',
  'HelloPaisa',
  'Nedbank',
  'Standard Bank',
];
final List<String> accountTypes = [
  'Select Account Type',
  'Cheque',
  'Savings',
  'Credit',
];

String? selectedBank;
List<String> banks = [];

String selectedService = 'Select Service';
String selectedAccountType = 'Select Account Type';

class BankingDetails {
  String selectedService;
  String selectedAccountType;
  String accountHolderName;
  String accountNumber;
  String referenceCode;

  BankingDetails({
    required this.selectedService,
    required this.selectedAccountType,
    required this.accountHolderName,
    required this.accountNumber,
    this.referenceCode = '', // Default to empty if not applicable
  });

  Map<String, dynamic> toJson() {
    return {
      'selectedService': selectedService,
      'selectedAccountType': selectedAccountType,
      'accountHolderName': accountHolderName,
      'accountNumber': accountNumber,
      'referenceCode': referenceCode,
    };
  }

  // Factory constructor for creating a new BankingDetails instance from a map.
  // This is useful for fetching document data from Firestore.
  factory BankingDetails.fromFirestore(Map<String, dynamic> firestore) {
    return BankingDetails(
      selectedService: firestore['selectedService'] ?? '',
      selectedAccountType: firestore['selectedAccountType'] ?? '',
      accountHolderName: firestore['accountHolderName'] ?? '',
      accountNumber: firestore['accountNumber'] ?? '',
      referenceCode: firestore['referenceCode'] ?? '',
    );
  }
}
