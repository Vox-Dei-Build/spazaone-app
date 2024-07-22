class SMSMessages {
  static const String creditConfirmationSMS = '''
Dear {customerName}, your recent Credit of -{amount} at {shopName} has been recorded. 

Your current balance is {balance}. Thank you for trusting {shopName}'s business!

From {shopName}
''';

  static const String paymentConfirmationSMS = '''
Dear {customerName}, your recent Payment of +{amount} at {shopName} has been recorded. 

Your current balance is {balance}. Thank you for paying {shopName}'s business and for being reliable!

From {shopName}
''';

  static const String onboardingSMS = '''
Welcome to {shopName}, {customerName}! No more books! Your account with {shopName} is now online.

Your current balance is R0,00. Thank you again for choosing {shopName}'s business!

From {shopName} 
''';

  static const String reminderSMS = '''
Hi {customerName}, your balance at {shopName} of {balance} is due. 

Please keep up to date with your payments and join the 98% of {customerName}'s customers who pay back on time or penalities will be charged. 

From {shopName}
''';
}
