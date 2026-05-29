import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:provider/provider.dart';

// snackbar_messages.dart
const String insufficientBalanceMessage =
    'App balance too low to send. Tap to top up.';

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
            title: Text("App balance too low",
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
            content: const Text(
                "You don't have enough app balance to send this message. "
                "Top up to keep sending SMS and WhatsApp updates."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context)
                      .pop(false); // Save record, no message sent.
                },
                child: Text("Save only",
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.account_balance_wallet, size: 18),
                label: Text("Top up now",
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
                onPressed: () {
                  Navigator.of(context).pop(false);
                  // PAS-UX-WTC: land on Top-Up directly so the merchant
                  // doesn't have to find the tab themselves.
                  Provider.of<AppModel>(context, listen: false)
                      .goToBilling(context,
                          initialTab: WalletInitialTab.topUp);
                },
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
        SnackBar(
          content: const Text(
            insufficientBalanceMessage,
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.amber.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Top up',
            textColor: Colors.white,
            onPressed: () {
              Provider.of<AppModel>(context, listen: false).goToBilling(
                context,
                initialTab: WalletInitialTab.topUp,
              );
            },
          ),
        ),
      );
    });
  }
}
