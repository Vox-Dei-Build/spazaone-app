import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/pages/wallet/widgets/notification_tile.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/widgets/top_up_tile.dart';

class TransactionHistoryTab extends StatelessWidget {
  const TransactionHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MergedHistory(userId: userId)),
          ],
        ),
      ),
    );
  }
}

/// 🟢 Merges Top-Up Transactions & Notifications in One Chronological List
class _MergedHistory extends StatelessWidget {
  final String userId;
  const _MergedHistory({required this.userId});

  @override
  Widget build(BuildContext context) {
    final transactionsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('topUpTransactions')
        .orderBy('createdAt', descending: true)
        .snapshots();

    final notificationsRef = FirebaseFirestore.instance
        .collection('notifications')
        .doc(userId)
        .collection('customer_notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<List<QuerySnapshot>>(
      stream: StreamZip([transactionsRef, notificationsRef]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData ||
            (snapshot.data![0].docs.isEmpty &&
                snapshot.data![1].docs.isEmpty)) {
          return const _EmptyState(message: "No transactions or messages yet.");
        }

        final transactions = snapshot.data![0].docs;
        final notifications = snapshot.data![1].docs;

        /// 🔥 Combine Both Lists & Sort by Timestamp
        final List<Map<String, dynamic>> mergedList = [];

        for (var tx in transactions) {
          mergedList.add({
            'type': 'top-up',
            'amount': tx['amount'] as num,
            'timestamp': (tx['createdAt'] as Timestamp).toDate(),
          });
        }

        for (var notification in notifications) {
          mergedList.add({
            'type': 'message',
            'message': notification['message'] as String,
            'messageCost': notification['messageCost'] as num,
            'phone': notification['customer_phone'] as String,
            'timestamp': (notification['timestamp'] as Timestamp).toDate(),
          });
        }

        mergedList.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        return ListView.separated(
          separatorBuilder: (_, __) => const Divider(
            color: Colors.grey,
            thickness: .3,
          ),
          itemCount: mergedList.length,
          itemBuilder: (context, index) {
            final item = mergedList[index];
            final timestamp = item['timestamp'];

            if (item['type'] == 'top-up') {
              return TopUpTile(amount: item['amount'], date: timestamp);
            } else {
              return NotificationTile(
                  message: item['message'],
                  messageCost: item['messageCost'],
                  phone: item['phone'],
                  date: timestamp);
            }
          },
        );
      },
    );
  }
}

/// 🟢 Empty State Widget
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 3),
        child: Text(
          message,
          style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.8, color: Colors.grey),
        ),
      ),
    );
  }
}
