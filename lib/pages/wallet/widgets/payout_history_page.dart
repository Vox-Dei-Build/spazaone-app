import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/widgets/icon_helper.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class PayoutHistoryPage extends StatefulWidget {
  @override
  _PayoutHistoryPageState createState() => _PayoutHistoryPageState();
}

class _PayoutHistoryPageState extends State<PayoutHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(onBack: false, title: 'Payout Request'),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('payoutRequests')
            .where('merchantId',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .orderBy('requestedOn', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No payout history found'));
          }

          final documents = snapshot.data!.docs;

          return ListView.builder(
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              if (!doc.exists) {
                // If the document does not exist, return a placeholder or error widget
                return ListTile(
                  leading: Icon(Icons.error),
                  title: Text('Error'),
                  subtitle: Text('Document does not exist'),
                );
              }

              // Cast the data to a Map<String, dynamic> type.
              var data = doc.data() as Map<String, dynamic>?;

              return GestureDetector(
                onTap: () {},
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.all(10.0),
                      visualDensity: const VisualDensity(horizontal: -2),
                      leading: data != null && data.containsKey('payoutStatus')
                          ? getIconForStatus(data['payoutStatus'])
                          : getIconForStatus(''),
                      title: Text(
                          '${data != null && data.containsKey('amount') ? CurrencyUtil.format(data['amount']) : 'R0.0'}'),
                      subtitle: Text(
                          'Status: ${data != null && data.containsKey('payoutStatus') ? formatStringToCamelCase(data['payoutStatus']) : 'Unknown'}'),
                      trailing: Text(
                          '${data != null && data.containsKey('requestedOn') ? DateFormat('dd/MM/yyyy, HH:mm').format((data['requestedOn'] as Timestamp).toDate()) : 'Unknown Date'}'),
                    ),
                    const Divider(
                      color: kHighLightColor,
                      height: 5,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
