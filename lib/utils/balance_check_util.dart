import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:provider/provider.dart';

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

    DocumentSnapshot walletSnapshot = await firestore
        .collection('users')
        .doc(merchantId)
        .collection('wallet')
        .doc('current')
        .get();

    double balance = (walletSnapshot['virtualBalance'] ?? 0).toDouble();

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

    DocumentSnapshot walletSnapshot = await firestore
        .collection('users')
        .doc(merchantId)
        .collection('wallet')
        .doc('current')
        .get();

    double balance = (walletSnapshot['virtualBalance'] ?? 0).toDouble();

    return balance >= cost;
  }

  static Future<bool> _showTopUpDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text("Insufficient Balance",
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
            content: const Text(
                "Your balance is too low to send messages. 📩 To keep your customers informed and engaged, please top up now and continue sending important updates seamlessly! 🔄💡"),
            actions: [
              TextButton(
                onPressed: () {
                  // Navigator.of(context).pop(false);
                  Provider.of<AppModel>(context, listen: false)
                      .handleNavigation(context, 4);
                  Navigator.pushNamed(context, Dashboard.id);
                },
                child: Text("Top Up Now",
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .pop(false); // ❌ Cancel → Do NOT send message
                },
                child: Text("Proceed Without Message",
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
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
