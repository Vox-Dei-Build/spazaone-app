import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';

class FullRepaymentReportPage extends StatefulWidget {
  final WalletState walletState;
  const FullRepaymentReportPage({super.key, required this.walletState});
  static const id = '/fullRepaymentReportPage';

  @override
  _FullRepaymentReportPage createState() => _FullRepaymentReportPage();
}

class _FullRepaymentReportPage extends State<FullRepaymentReportPage> {
  late WalletState walletState;

  @override
  void initState() {
    super.initState();
    walletState = widget.walletState;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Cash Advance Report'),
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Overview',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 2)),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            _infoRow('Total Given',
                CurrencyUtil.format(walletState.totalCashAdvanceGiven)),
            _infoRow('Total Repaid',
                CurrencyUtil.format(walletState.totalCashAdvanceRepaid)),
            _infoRow('Current Due',
                CurrencyUtil.format(walletState.cashAdvanceBalance * 1.1)),
            _infoRow(
                'Penalty Applied', CurrencyUtil.format(walletState.penaltyFee)),
            _infoRow('Suspension Status',
                walletState.accountSuspended ? 'Suspended' : 'Active'),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            Text('Repayment History',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 2)),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Expanded(
              child: ListView.builder(
                itemCount: walletState.repaymentHistory.length,
                itemBuilder: (context, index) {
                  final repayment = walletState.repaymentHistory[index];
                  return Card(
                    margin: EdgeInsets.only(
                        bottom: SizeConfig.heightMultiplier * 1.5),
                    child: ListTile(
                      title: Text(CurrencyUtil.format(repayment['amount']),
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.8,
                            fontWeight: FontWeight.bold,
                          )),
                      subtitle: Text(
                          'Date: ${DateFormat('dd MMM yyyy').format(repayment['date'])}\n'
                          'Method: ${repayment['method']}\n'
                          'Status: ${repayment['status']}',
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.6,
                          )),
                      trailing: Text(repayment['reference'],
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 1.6,
              )),
        ],
      ),
    );
  }
}
