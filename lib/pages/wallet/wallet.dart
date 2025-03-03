import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/icon_action_button.dart';
import 'package:pasella/pages/wallet/widgets/info_page.dart';
import 'package:pasella/pages/wallet/widgets/payout_history_page.dart';
import 'package:pasella/pages/wallet/widgets/payout_request.dart';
import 'package:pasella/utils/currency_util.dart';
import 'widgets/banking_details.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({Key? key}) : super(key: key);

  @override
  _WalletPageState createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  late WalletViewModel walletViewModel;
  bool hasBankAccount = false;
  bool hasPendingRequest = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    walletViewModel = WalletViewModel();
    _init();
  }

  _init() async {
    setState(() {
      isLoading = true;
    });
    try {
      bool localHasBankAccount = await walletViewModel.hasBankAccount();
      bool localHasPendingRequest =
          await walletViewModel.hasPendingPayoutRequest() ||
              await walletViewModel.hasProcessingPayoutRequest();

      setState(() {
        hasBankAccount = localHasBankAccount;
        hasPendingRequest = localHasPendingRequest;
      });
    } catch (e) {
      print(e);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    walletViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 4),
          child: Column(
            children: [
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              const PageHeader(),
              const SizedBox(height: 40.0),
              StreamBuilder<double>(
                stream: walletViewModel.getVirtualBalanceStream(),
                builder: (context, snapshot) {
                  // Check for errors or lack of data
                  if (snapshot.hasError) {
                    return Text("Error: ${snapshot.error}");
                  } else if (!snapshot.hasData) {
                    return const CircularProgressIndicator(); // or some placeholder
                  }

                  // Display the balance
                  double balance = snapshot.data!;
                  return Column(
                    children: [
                      const Icon(
                        Icons.wallet_outlined,
                        color: kSecondaryColor,
                        size: 40.0,
                      ),
                      const SizedBox(height: 8),
                      Text('Your Balance',
                          style:
                              Theme.of(context).textTheme.titleMedium!.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                      const SizedBox(height: 10),
                      Text(CurrencyUtil.format(balance),
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge!
                              .copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconActionButton(
                      icon: isLoading
                          ? Icons.pending_rounded
                          : hasBankAccount
                              ? Icons.credit_score_rounded
                              : Icons.add_card_rounded,
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const AddBankingDetailsPage(),
                            ),
                          ).then((_) async {
                            _init();
                          }),
                      color: isLoading
                          ? Colors.green
                          : hasBankAccount
                              ? Colors.green
                              : kSecondaryColor,
                      label: hasBankAccount ? 'Edit Account' : 'Add Account'),
                  IconActionButton(
                    icon: Icons.history_rounded,
                    color: kSecondaryColor,
                    disabled: false, // Enabled the button
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => PayoutHistoryPage()),
                      ).then((_) async {
                        _init();
                      });
                    },
                    label: 'History',
                  ),
                  IconActionButton(
                    icon: Icons.info_outline_rounded,
                    color: kSecondaryColor,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const InfoPage()),
                      );
                    },
                    label: 'Info', // Change this to suit your needs
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
              StreamBuilder<double>(
                  stream: walletViewModel.getVirtualBalanceStream(),
                  builder: (context, snapshot) {
                    // Check for errors or lack of data
                    if (snapshot.hasError) {
                      return Text("Error: ${snapshot.error}");
                    } else if (!snapshot.hasData) {
                      return const CircularProgressIndicator(); // or some placeholder
                    }

                    double balance = snapshot.data!;
                    bool requestPayoutCondition =
                        !hasPendingRequest && hasBankAccount && balance > 0;
                    String disabledReason =
                        ""; // This string will hold the reason why the button is disabled

                    if (hasPendingRequest) {
                      disabledReason = "A payout request is currently pending.";
                    } else if (!hasBankAccount) {
                      disabledReason =
                          "Please add a bank account to request a payout.";
                    } else if (balance <= 0) {
                      disabledReason =
                          "Insufficient balance to request a payout.";
                    }

                    return isLoading
                        ? const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.green))
                        : Column(
                            children: [
                              ElevatedButton(
                                onPressed: requestPayoutCondition
                                    ? () {
                                        // Navigation to PayoutPage with balance
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const PayoutPage(),
                                            settings: RouteSettings(
                                                arguments: balance),
                                          ),
                                        ).then((_) async {
                                          // Refresh bank account and pending request status after returning from PayoutPage
                                          _init();
                                        });
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: requestPayoutCondition
                                      ? Colors.green
                                      : Colors.grey, // Enabled if balance > 0
                                  disabledBackgroundColor: requestPayoutCondition
                                      ? Colors.green
                                      : Colors
                                          .grey, // Color when button is disabled
                                  foregroundColor: Colors.white,
                                ), // Button is disabled
                                child: const Text('Request Payout'),
                              ),
                              const SizedBox(
                                  height:
                                      8), // Add some space between the button and the explanation text
                              if (!requestPayoutCondition) // Only show this text if the button is disabled
                                Text(
                                  disabledReason,
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize:
                                          14), // Styling for the reason text
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          );
                  }),
            ],
          ),
        ),
      ),
    );
  }
}
