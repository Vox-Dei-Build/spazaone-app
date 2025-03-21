import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/pages/wallet/widgets/icon_helper.dart';
import 'package:pasella/config/size_config.dart';

class PayoutHistoryTab extends StatelessWidget {
  const PayoutHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('payoutRequests')
            .where('merchantId',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .orderBy('requestedOn', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No payout history found'));
          }

          final documents = snapshot.data!.docs;

          return ListView.separated(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 2,
              horizontal: SizeConfig.heightMultiplier * 2,
            ),
            itemCount: documents.length,
            separatorBuilder: (_, __) => Divider(
              height: SizeConfig.heightMultiplier * 2,
              thickness: 1,
              color: Colors.grey.shade300,
            ),
            itemBuilder: (context, index) {
              final data = documents[index].data() as Map<String, dynamic>?;
              final amount = data != null && data.containsKey('amount')
                  ? CurrencyUtil.format(data['amount'])
                  : 'R0.0';
              final status = data?['payoutStatus'] ?? 'Unknown';
              final date = data != null && data.containsKey('requestedOn')
                  ? DateFormat('dd MMM yyyy, HH:mm')
                      .format((data['requestedOn'] as Timestamp).toDate())
                  : 'Unknown Date';

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  getIconForStatus(status),
                  SizedBox(width: SizeConfig.blockSizeHorizontal * 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amount,
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 2,
                              fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                        Text(
                          date,
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.6,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: SizeConfig.blockSizeHorizontal * 2,
                      vertical: SizeConfig.heightMultiplier * 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(
                          SizeConfig.blockSizeHorizontal * 2),
                    ),
                    child: Text(
                      status.toString().toUpperCase(),
                      style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
