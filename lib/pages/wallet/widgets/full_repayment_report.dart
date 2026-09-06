import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/wallet_utils.dart';

class FullRepaymentReportPage extends StatefulWidget {
  final WalletState walletState;
  const FullRepaymentReportPage({
    super.key,
    required this.walletState,
    this.breakdownLoader = WalletUtils.computeBreakdown,
  });
  final Future<WalletBreakdown> Function(WalletState) breakdownLoader;
  static const id = '/fullRepaymentReportPage';

  @override
  State<FullRepaymentReportPage> createState() => _FullRepaymentReportPage();
}

class _FullRepaymentReportPage extends State<FullRepaymentReportPage> {
  late WalletState walletState;
  // PAS-UX-12: compute the fee breakdown once instead of spawning
  // three sibling FutureBuilders that each hit RemoteConfig in
  // parallel and resolve at different frames.
  late Future<WalletBreakdown> _breakdown;

  @override
  void initState() {
    super.initState();
    walletState = widget.walletState;
    _breakdown = widget.breakdownLoader(walletState);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Cash Advance Report'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<WalletBreakdown>(
          future: _breakdown,
          builder: (context, snapshot) {
            final b = snapshot.data ?? WalletBreakdown.loading;
            return ListView(
              children: [
                const Text('Overview',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                _infoRow('Total Given',
                    CurrencyUtil.format(walletState.totalCashAdvanceGiven)),
                _infoRow('Total Repaid',
                    CurrencyUtil.format(walletState.totalCashAdvanceRepaid)),
                _infoRow('Fee Charged', b.advanceFee),
                _infoRow('Bank Fee', b.bankFee),
                _infoRow('Penalty Applied', b.penaltyFee),
                _infoRow('Current Due', b.totalOwed),
                _infoRow('Suspended', b.suspended),
                const SizedBox(height: 24),
                const Text('Repayment History',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: walletState.repaymentHistory.length,
                  itemBuilder: (context, index) {
                    final repayment = walletState.repaymentHistory[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                            CurrencyUtil.format(
                                (repayment['amount'] as num).toDouble()),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            )),
                        subtitle: Text(
                            'Date: ${DateFormat('dd MMM yyyy').format(repayment['date'])}\n'
                            'Method: ${repayment['method']}\n'
                            'Status: ${repayment['status']}\n'
                            'Reference: ${repayment['reference']}',
                            style: const TextStyle(
                              fontSize: 13,
                            )),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              )),
        ],
      ),
    );
  }
}
