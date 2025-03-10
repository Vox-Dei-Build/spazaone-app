import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// snackbar_messages.dart
const String insufficientBalanceMessage =
    'Insufficient balance for sending message. Please top up.';

class BalanceCheckUtil {
  static Future<bool> checkBalanceAndProceed(
    BuildContext context,
    String merchantId,
    double messageCost,
  ) async {
    // 🔹 Fetch Merchant's Balance
    final firestore = FirebaseFirestore.instance;

    DocumentSnapshot merchantSnapshot =
        await firestore.collection('users').doc(merchantId).get();
    double balance = (merchantSnapshot['virtualBalance'] ?? 0).toDouble();

    if (balance >= messageCost) {
      return true; // ✅ Enough balance, proceed
    }

    // 🔹 Show the top-up dialog
    bool shouldProceedWithMessage = await _showTopUpDialog(context);

    return shouldProceedWithMessage; // ❌ False means skip sending the message
  }

  static Future<bool> hasSufficientBalance(
      String merchantId, double cost) async {
    final firestore = FirebaseFirestore.instance;
    DocumentSnapshot merchantSnapshot =
        await firestore.collection('users').doc(merchantId).get();

    double balance = (merchantSnapshot['virtualBalance'] ?? 0).toDouble();

    return balance >= cost;
  }

  static Future<bool> _showTopUpDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Insufficient Balance"),
            content: const Text(
                "Your balance is too low to send messages. Please top up to continue."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .pop(false); // ❌ Cancel → Do NOT send message
                },
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false); // ❌ Exit without sending
                  Navigator.pushNamed(
                      context, '/wallet'); // 🔄 Redirect to Wallet
                },
                child: const Text("Top Up Now"),
              ),
            ],
          ),
        ) ??
        false; // Default to false if dialog is dismissed
  }
}

class SnackbarComponents {
  static void showInsufficientBalance(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            insufficientBalanceMessage,
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    });
  }
}
