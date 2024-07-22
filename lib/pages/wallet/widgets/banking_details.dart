import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/wallet/wallet_model.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/bank_details_fields.dart';
import 'package:pasella/pages/wallet/widgets/flash_hello_paisa_details_widget.dart';
import 'package:pasella/pages/wallet/widgets/save_widget.dart';
import 'package:pasella/pages/wallet/widgets/service_selection_widget.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

class AddBankingDetailsPage extends StatefulWidget {
  const AddBankingDetailsPage({super.key});
  static const id = '/addBankingDetailsPage';
  @override
  _AddBankingDetailsPageState createState() => _AddBankingDetailsPageState();
}

class _AddBankingDetailsPageState extends State<AddBankingDetailsPage> {
  late WalletViewModel walletViewModel;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    walletViewModel = WalletViewModel();
    _initializeViewModel();
  }

  Future<void> _initializeViewModel() async {
    await walletViewModel.initializeBankingDetails();
    if (walletViewModel.editingDocumentId != null) {
      BankingDetails? bankingDetails = await walletViewModel
          .fetchBankingDetails(walletViewModel.editingDocumentId!);

      if (bankingDetails != null) {
        setState(() {
          // Now using BankingDetails to set the fields

          selectedService = bankingDetails.selectedService;
          selectedAccountType = bankingDetails.selectedAccountType;

          banks = serviceBanks[selectedService] ?? [];
          selectedBank = walletViewModel.findBankByAccountNumber(
              selectedService, bankingDetails.accountNumber);

          walletViewModel.accountHolderName.text =
              bankingDetails.accountHolderName;
          walletViewModel.accountNumber.text = bankingDetails.accountNumber;
          if (selectedService == 'Flash') {
            walletViewModel.flashVendorId.text = bankingDetails.referenceCode;
          } else if (selectedService == 'HelloPaisa') {
            walletViewModel.helloPaisaAccountId.text =
                bankingDetails.referenceCode;
          }
          _isLoading = false; // Indicate that loading has finished
        });
      } else {
        setState(() {
          _isLoading =
              false; // Even if there is no banking detail, loading is done.
        });
      }
    } else {
      setState(() {
        _isLoading =
            false; // Indicate that loading has finished if there is no document ID
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
        appBar: CustomAppBar(title: 'Add Banking Details'),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: LayoutConstants.padding20Horizontal,
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    if (_isLoading)
                      Center(
                        // This centers in the middle of the available space
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      ServiceSelectionWidget(
                        selectedService: selectedService,
                        services: services,
                        onChanged: (newValue) {
                          setState(() {
                            walletViewModel.resetFields();
                            selectedService = newValue!;
                            banks = serviceBanks[selectedService] ?? [];
                            selectedBank = banks.isNotEmpty
                                ? banks.first
                                : null; // Default to first bank
                            // Set predefined account name based on the service
                            walletViewModel.accountHolderName.text =
                                predefinedAccountDetails[selectedService]
                                        ?['AccountName'] ??
                                    '';

                            walletViewModel.accountNumber.text =
                                predefinedAccountDetails[selectedService]
                                        ?[selectedBank] ??
                                    '';
                          });
                        },
                      ),
                      // Conditional rendering based on selectedService
                      if (selectedService == 'Flash' ||
                          selectedService == 'HelloPaisa')
                        FlashHelloPaisaDetailsWidget(
                          vendorIdController: walletViewModel.flashVendorId,
                          referenceNumberController:
                              walletViewModel.helloPaisaAccountId,
                          selectedService: selectedService,
                          banks:
                              banks, // List of banks based on the selected service
                          selectedBank: selectedBank,
                          onBankChanged: (newBank) {
                            setState(() {
                              selectedBank = newBank;
                              // Update account number based on new bank selection
                              walletViewModel.accountNumber.text =
                                  predefinedAccountDetails[selectedService]
                                          ?[newBank] ??
                                      '';
                            });
                          },
                          accountDetails:
                              predefinedAccountDetails[selectedService] ?? {},
                        ),
                      if (selectedService != 'Select Service' &&
                          selectedService != 'Flash' &&
                          selectedService != 'HelloPaisa')
                        BankDetailsWidget(
                          accountHolderNameController:
                              walletViewModel.accountHolderName,
                          accountNumberController:
                              walletViewModel.accountNumber,
                          selectedAccountType: selectedAccountType,
                          onAccountTypeChanged: (String? newType) {
                            setState(() {
                              selectedAccountType = newType!;
                            });
                          },
                        ),
                      SavingButtonWidget(
                        formKey: _formKey,
                        isProcessing: walletViewModel.isProcessing,
                        selectedService: selectedService,
                        selectedAccountType: selectedAccountType,
                        onSave: (BuildContext context, String selectedService,
                            String selectedAccountType) async {
                          await walletViewModel.saveBankingDetails(
                              context, selectedService, selectedAccountType);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ));
  }
}
