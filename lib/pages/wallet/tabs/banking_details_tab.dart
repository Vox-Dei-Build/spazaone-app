import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/widgets/private_region.dart';

class BankingDetailsTab extends StatefulWidget {
  const BankingDetailsTab({super.key});

  @override
  State<BankingDetailsTab> createState() => _BankingDetailsTabState();
}

class _BankingDetailsTabState extends State<BankingDetailsTab> {
  late WalletViewModel walletViewModel = WalletViewModel();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBankingDetails();
  }

  @override
  void dispose() {
    walletViewModel.dispose();
    super.dispose();
  }

  Future<void> _loadBankingDetails() async {
    setState(() => isLoading = true);
    await walletViewModel.initializeBankingDetails();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    if (walletViewModel.editingDocumentId == null) ...[
                      Text(
                        "You haven't added any banking details yet.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: SizeConfig.textMultiplier * 1.5),
                      ),
                    ] else ...[
                      _bankingDetailsSummary(walletViewModel),
                    ],
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    CustomButton(
                      title: 'Add / Edit Banking Details',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddBankingDetailsPage(
                              walletViewModel: walletViewModel,
                            ),
                          ),
                        );
                      },
                      color: Colors.green,
                      icon: Icons.add,
                      fontSize: SizeConfig.textMultiplier * 2,
                      width: SizeConfig.imageSizeMultiplier * 65,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _bankingDetailsSummary(WalletViewModel viewModel) {
    // Read-only summary -- account number etc. visible. Mask the whole Card.
    return PrivateRegion(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("Bank", viewModel.bankName.text),
              _infoRow("Account Holder Name", viewModel.accountHolderName.text),
              _infoRow("Account Number", viewModel.accountNumber.text),
              _infoRow("Account Type", viewModel.accountType.text),
              _infoRow("Branch Code", viewModel.branchCode.text),
              _infoRow("Reference", viewModel.reference.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
