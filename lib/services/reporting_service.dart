import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pasella/services/crash_service.dart';

class ReportingService {
  final String currentUserId;

  ReportingService(this.currentUserId);

  // Helper list to get month names
  List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  Future<List<DocumentSnapshot>> fetchAllCustomers() async {
    try {
      return await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .get()
          .then((snapshot) => snapshot.docs);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching customers',
      );
      return [];
    }
  }

  Future<List<DocumentSnapshot>> _fetchTransactionsForCustomer(
      DocumentReference customerRef,
      DateTime startDate,
      DateTime endDate,
      String? type) async {
    try {
      Query query = customerRef
          .collection('transactions')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate);

      if (type != null) {
        query = query.where('type', isEqualTo: type);
      }

      return await query.get().then((snapshot) => snapshot.docs);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching transactions for customer',
      );
      return [];
    }
  }

  Future<void> _processTransactions(
      List<DocumentSnapshot>? customerDocs,
      DateTime startDate,
      DateTime endDate,
      String? type,
      void Function(DocumentSnapshot) processTransaction,
      {DocumentReference? singleCustomerRef}) async {
    List<DocumentReference> customerRefs = [];

    if (customerDocs != null) {
      customerRefs = customerDocs.map((doc) => doc.reference).toList();
    } else if (singleCustomerRef != null) {
      customerRefs.add(singleCustomerRef);
    } else {
      return; // Neither DocumentSnapshot list nor single DocumentReference provided
    }

    for (DocumentReference customerRef in customerRefs) {
      try {
        List<DocumentSnapshot> transactions =
            await _fetchTransactionsForCustomer(
          customerRef,
          startDate,
          endDate,
          type,
        );
        for (DocumentSnapshot transaction in transactions) {
          processTransaction(transaction);
        }
      } catch (e, st) {
        await CrashService.instance.recordNonFatal(
          e,
          st,
          reason: 'reporting: Error processing transactions',
        );
      }
    }
  }

  Future<void> _processTransactionsForSingleCustomer(
      DocumentReference customerRef,
      DateTime startDate,
      DateTime endDate,
      String transactionType,
      void Function(DocumentSnapshot transaction) callback) async {
    // Convert the single DocumentReference to a List<DocumentSnapshot>
    DocumentSnapshot customerDoc = await customerRef.get();
    List<DocumentSnapshot> customerDocs = [customerDoc];

    // Call the original _processTransactions method
    await _processTransactions(
        customerDocs, startDate, endDate, transactionType, callback);
  }

  Future<Map<String, dynamic>> generateReport(
      DateTime startDate, DateTime endDate, int yearly_period) async {
    List<DocumentSnapshot> allCustomers = await fetchAllCustomers();

    int totalNumberOfCustomers = await getTotalCustomers(allCustomers);
    String monthWithHighestLoanIssuance =
        await getMonthWithHighestLoanIssuance(allCustomers, yearly_period);
    int totalRemindersSent =
        await getTotalRemindersSent(allCustomers, startDate, endDate);
    double totalPayments =
        await getTotalPaymentsReceived(allCustomers, startDate, endDate);
    double totalCredit =
        await fetchTotalCreditForPeriod(allCustomers, startDate, endDate);
    double peakCreditSize =
        await calculatePeakCreditSize(allCustomers, startDate, endDate);
    List<String> customersWithNPAs =
        await fetchCustomersWithNPAs(currentUserId, startDate, endDate);
    int totalNumberofNPAs = customersWithNPAs.length;
    double creditCycle =
        await calculateCreditCycle(allCustomers, startDate, endDate);
    double totalOustandingAmount =
        await getTotalOutstandingAmount(allCustomers, startDate, endDate);
    int totalAmountForLoans =
        await getTotalLoanTransactions(allCustomers, startDate, endDate);
    double avgLoanAmount =
        await getAverageLoanAmount(allCustomers, startDate, endDate);
    double avgPaymentAmount =
        await getAveragePaymentAmount(allCustomers, startDate, endDate);
    double avgTransactionAmount =
        await getAverageTransactionValue(allCustomers, startDate, endDate);
    double avgTransactionPerDay = await calculateAverageTransactionsPerDay(
        allCustomers, startDate, endDate);
    String dateWithTheHighestTransactions =
        await getDateWithHighestTransactions(allCustomers, startDate, endDate);
    int avgRepaymentTime =
        await getAverageRepaymentTime(allCustomers, startDate, endDate);
    double nplRatio =
        await calculateNPLRatio(totalNumberofNPAs, totalAmountForLoans);

    return {
      'totalNumberOfCustomers': totalNumberOfCustomers,
      'monthWithHighestLoanIssuance': monthWithHighestLoanIssuance,
      'totalRemindersSent': totalRemindersSent,
      'totalPayments': totalPayments,
      'totalCredit': totalCredit,
      'peakCreditSize': peakCreditSize,
      'totalNumberofNPAs': totalNumberofNPAs,
      'customersWithNPAs': customersWithNPAs,
      'creditCycle': creditCycle,
      'totalOustandingAmount': totalOustandingAmount,
      'totalAmountForLoans': totalAmountForLoans,
      'avgLoanAmount': avgLoanAmount,
      'avgPaymentAmount': avgPaymentAmount,
      'avgTransactionAmount': avgTransactionAmount,
      'avgTransactionPerDay': avgTransactionPerDay,
      'dateWithTheHighestTransactions': dateWithTheHighestTransactions,
      'avgRepaymentTime': avgRepaymentTime,
      'nplRatio': nplRatio,
    };
  }

  Future<double> calculateNPLRatio(
      int totalNumberofNPAs, int totalAmountForLoans) async {
    if (totalAmountForLoans == 0) {
      return 0.0; // To avoid division by zero
    }

    return (totalNumberofNPAs / totalAmountForLoans) * 100;
  }

  Future<int> getTotalCustomers(List<DocumentSnapshot> customerDocs) async {
    try {
      return customerDocs.length;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching total customers',
      );
      return 0;
    }
  }

  Future<String> getMonthWithHighestLoanIssuance(
      List<DocumentSnapshot> customerDocs, int yearly_period) async {
    Map<DateTime, double> monthlyTotals = {};

    // Define the custom processing function
    void _aggregateLoansByMonth(DocumentSnapshot transactionDoc) {
      Map<String, dynamic> data = transactionDoc.data() as Map<String, dynamic>;
      DateTime date = (data['date'] as Timestamp).toDate();
      DateTime monthKey = DateTime(date.year, date.month, 1);
      monthlyTotals[monthKey] =
          (monthlyTotals[monthKey] ?? 0.0) + (data['amount'] as num).toDouble();
    }

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        await _processTransactions(
          null,
          DateTime.now().subtract(Duration(days: yearly_period)),
          DateTime.now(),
          'Credit',
          _aggregateLoansByMonth,
          singleCustomerRef: customerDoc.reference,
        );
      }

      if (monthlyTotals.isEmpty) return "No Data";

      DateTime maxMonth = monthlyTotals.keys.first;
      for (DateTime month in monthlyTotals.keys) {
        if (monthlyTotals[month]! > monthlyTotals[maxMonth]!) {
          maxMonth = month;
        }
      }
      return monthNames[maxMonth.month - 1];
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error determining month with highest loan issuance',
      );
      return "Error";
    }
  }

  Future<int> getTotalRemindersSent(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    int totalReminders = 0;

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        QuerySnapshot reminderSnapshots = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('customers')
            .doc(customerDoc.id)
            .collection('reminders')
            .where('dateSent', isGreaterThanOrEqualTo: startDate)
            .where('dateSent', isLessThanOrEqualTo: endDate)
            .get();
        totalReminders += reminderSnapshots.docs.length;
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching total reminders sent',
      );
      return Future.error("Error fetching total reminders sent: $e");
    }
    return totalReminders;
  }

  Future<double> getTotalPaymentsReceived(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    double totalPayments = 0.0;
    try {
      await _processTransactions(customerDocs, startDate, endDate, 'Payment',
          (transaction) {
        Map<String, dynamic> data = transaction.data() as Map<String, dynamic>;
        totalPayments += (data['amount'] as num).toDouble();
      });
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating total payments received',
      );
    }
    return totalPayments;
  }

  Future<double> fetchTotalCreditForPeriod(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    double totalCredit = 0.0;
    try {
      await _processTransactions(customerDocs, startDate, endDate, 'Credit',
          (transaction) {
        Map<String, dynamic> data = transaction.data() as Map<String, dynamic>;
        totalCredit += (data['amount'] as num).toDouble();
      });
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating credit size',
      );
    }
    return totalCredit;
  }

  Future<double> calculatePeakCreditSize(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    double peakCreditSize = 0.0;
    try {
      await _processTransactions(customerDocs, startDate, endDate, 'Credit',
          (transaction) {
        Map<String, dynamic> data = transaction.data() as Map<String, dynamic>;
        double currentCredit = (data['amount'] as num).toDouble();
        if (currentCredit > peakCreditSize) {
          peakCreditSize = currentCredit;
        }
      });
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating peak credit size',
      );
    }
    return peakCreditSize;
  }

  Future<List<String>> fetchCustomersWithNPAs(
      String currentUserId, DateTime startDate, DateTime endDate) async {
    try {
      // Keep the query beneath the selected store. The previous global
      // collection-group query crossed every merchant namespace and cannot be
      // authorized by tenant-scoped Firestore rules.
      final customerSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .get();
      final npaCustomerIds = <String>[];

      for (final customer in customerSnapshot.docs) {
        final dueCredits = await customer.reference
            .collection('transactions')
            .where('date', isGreaterThanOrEqualTo: startDate)
            .where('date', isLessThanOrEqualTo: endDate)
            .where('type', isEqualTo: 'Credit')
            .where('status', isEqualTo: 'DUE')
            .limit(1)
            .get();
        if (dueCredits.docs.isNotEmpty) {
          npaCustomerIds.add(customer.id);
        }
      }

      // Check if the list is empty before using whereIn filter
      if (npaCustomerIds.isEmpty) {
        return [];
      }

      // Fetch customer names
      return await fetchCustomerNames(npaCustomerIds, currentUserId);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching customers with NPAs',
      );
      return [];
    }
  }

  Future<List<String>> fetchCustomerNames(
      List<String> customerIds, String currentUserId) async {
    List<String> customerNames = [];

    // Check if the list is empty
    if (customerIds.isEmpty) {
      return [];
    }

    // Split the list into chunks of 30
    for (int i = 0; i < customerIds.length; i += 30) {
      List<String> chunk =
          customerIds.sublist(i, min(i + 30, customerIds.length));

      try {
        QuerySnapshot querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('customers')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (DocumentSnapshot doc in querySnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          customerNames.add(data['name'] ?? 'Unknown Name');
        }
      } catch (e, st) {
        await CrashService.instance.recordNonFatal(
          e,
          st,
          reason: 'reporting: Error fetching customer names for chunk',
        );
        customerNames.add('Error Fetching Customer');
      }
    }

    return customerNames;
  }

  Future<double> calculateCreditCycle(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    List<int> creditCycles = [];

    await _processTransactions(customerDocs, startDate, endDate, 'Credit',
        (creditTransaction) async {
      DateTime creditDate =
          (creditTransaction.data() as Map<String, dynamic>)['date'].toDate();

      // Get the DocumentReference of the customer from the creditTransaction
      DocumentReference<Object?> customerRef = creditTransaction
          .reference.parent.parent as DocumentReference<Object?>;

      List<DocumentSnapshot> paymentTransactions =
          await _fetchTransactionsForCustomer(
        customerRef,
        creditDate,
        endDate,
        'Payment',
      );

      if (paymentTransactions.isNotEmpty) {
        DateTime paymentDate =
            (paymentTransactions.first.data() as Map<String, dynamic>)['date']
                .toDate();

        int daysDifference = paymentDate.difference(creditDate).inDays;
        creditCycles.add(daysDifference);
      }
    });

    if (creditCycles.isEmpty) {
      return 0.0;
    }

    double averageCreditCycle =
        creditCycles.reduce((a, b) => a + b) / creditCycles.length;
    return averageCreditCycle;
  }

  Future<double> getTotalOutstandingAmount(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    try {
      double totalLoans =
          await fetchTotalCreditForPeriod(customerDocs, startDate, endDate);
      double totalPayments =
          await getTotalPaymentsReceived(customerDocs, startDate, endDate);
      return totalLoans - totalPayments;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating total outstanding amount',
      );
      return 0.0;
    }
  }

  Future<int> getTotalLoanTransactions(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    int totalLoanTransactions = 0;

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        await _processTransactionsForSingleCustomer(
            customerDoc.reference, startDate, endDate, 'Credit', (transaction) {
          totalLoanTransactions++;
        });
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error fetching total loan transactions',
      );
      return 0;
    }

    return totalLoanTransactions;
  }

  Future<double> getAverageLoanAmount(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    try {
      double totalLoans =
          await fetchTotalCreditForPeriod(customerDocs, startDate, endDate);
      int totalLoanTransactions =
          await getTotalLoanTransactions(customerDocs, startDate, endDate);
      if (totalLoanTransactions == 0) return 0.0; // Avoid division by zero
      return totalLoans / totalLoanTransactions;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating average loan amount',
      );
      return 0.0;
    }
  }

  Future<double> getAveragePaymentAmount(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    double totalPaymentAmount = 0.0;
    int totalPaymentTransactions = 0;

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        await _processTransactions([customerDoc], startDate, endDate, 'Payment',
            (transaction) {
          Map<String, dynamic> data =
              transaction.data() as Map<String, dynamic>;
          totalPaymentAmount += (data['amount'] as num).toDouble();
          totalPaymentTransactions++;
        });
      }

      if (totalPaymentTransactions == 0) return 0.0; // Avoid division by zero

      return totalPaymentAmount / totalPaymentTransactions;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating average payment amount',
      );
      return 0.0;
    }
  }

  Future<double> getAverageTransactionValue(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    double totalTransactionAmount = 0.0;
    int totalTransactions = 0;

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        // Process credit transactions
        await _processTransactions([customerDoc], startDate, endDate, 'Credit',
            (transaction) {
          Map<String, dynamic> data =
              transaction.data() as Map<String, dynamic>;
          totalTransactionAmount += (data['amount'] as num).toDouble();
          totalTransactions++;
        });

        // Process payment transactions
        await _processTransactions([customerDoc], startDate, endDate, 'Payment',
            (transaction) {
          Map<String, dynamic> data =
              transaction.data() as Map<String, dynamic>;
          totalTransactionAmount += (data['amount'] as num).toDouble();
          totalTransactions++;
        });
      }

      if (totalTransactions == 0) return 0.0; // Avoid division by zero

      return totalTransactionAmount / totalTransactions;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating average transaction value',
      );
      return 0.0;
    }
  }

  Future<double> calculateAverageTransactionsPerDay(
      List<DocumentSnapshot> customerDocs,
      DateTime startDate,
      DateTime endDate) async {
    int totalTransactions = 0;

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        // Process all transactions within the period
        await _processTransactions([customerDoc], startDate, endDate, null,
            (transaction) {
          totalTransactions++;
        });
      }

      int daysDifference = endDate.difference(startDate).inDays +
          1; // +1 to include both start and end dates

      double averageTransactions =
          totalTransactions / daysDifference.toDouble();
      return double.parse(averageTransactions.toStringAsFixed(2));
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating average transactions per day',
      );
      return 0.0;
    }
  }

  Future<String> getDateWithHighestTransactions(
      List<DocumentSnapshot> customerDocs,
      DateTime startDate,
      DateTime endDate) async {
    Map<DateTime, int> transactionCounts = {};

    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        // Process all transactions within the period
        await _processTransactions([customerDoc], startDate, endDate, null,
            (transaction) {
          DateTime date =
              (transaction.data() as Map<String, dynamic>)['date'].toDate();
          transactionCounts[date] = (transactionCounts[date] ?? 0) + 1;
        });
      }

      if (transactionCounts.isEmpty) return '';

      DateTime maxDate = transactionCounts.keys.first;
      for (DateTime date in transactionCounts.keys) {
        if (transactionCounts[date]! > transactionCounts[maxDate]!) {
          maxDate = date;
        }
      }

      return DateFormat('MMMM d, y').format(maxDate);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error determining date with highest transactions',
      );
      return '';
    }
  }

  Future<int> getAverageRepaymentTime(List<DocumentSnapshot> customerDocs,
      DateTime startDate, DateTime endDate) async {
    List<int> repaymentDurations = [];
    try {
      for (DocumentSnapshot customerDoc in customerDocs) {
        await _processTransactions([customerDoc], startDate, endDate, 'Credit',
            (creditTransaction) {
          Map<String, dynamic> creditData =
              creditTransaction.data() as Map<String, dynamic>;
          DateTime creditDate = (creditData['date'] as Timestamp).toDate();
          double creditAmount = (creditData['amount'] as num).toDouble();

          double totalPayments = 0.0;
          DateTime repaymentDate = creditDate;

          _processTransactions(
              [customerDoc], creditDate, DateTime.now(), 'Payment',
              (paymentTransaction) {
            Map<String, dynamic> paymentData =
                paymentTransaction.data() as Map<String, dynamic>;
            totalPayments += (paymentData['amount'] as num).toDouble();
            DateTime currentPaymentDate =
                (paymentData['date'] as Timestamp).toDate();
            if (currentPaymentDate.isAfter(repaymentDate)) {
              repaymentDate = currentPaymentDate;
            }
          });

          if (totalPayments >= creditAmount) {
            int daysDifference = repaymentDate.difference(creditDate).inDays;
            repaymentDurations.add(daysDifference);
          }
        });
      }

      if (repaymentDurations.isEmpty) return 0;
      int totalRepaymentDays = repaymentDurations.reduce((a, b) => a + b);
      return totalRepaymentDays ~/ repaymentDurations.length;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'reporting: Error calculating average repayment time',
      );
      return 0;
    }
  }
}
