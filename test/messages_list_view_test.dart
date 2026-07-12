import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';

void main() {
  testWidgets('long conversations settle on the newest message',
      (tester) async {
    final now = DateTime(2026, 7, 12, 5);
    final messages = List<Map<String, dynamic>>.generate(50, (index) {
      final isLatest = index == 49;
      return {
        'id': 'message-$index',
        'message': isLatest
            ? 'LATEST_MESSAGE'
            : 'Older message $index\nwith variable-height content\nline three',
        'dateSent': now.add(Duration(minutes: index)),
        'direction': 'outbound',
        'isWhatsApp': true,
        'status': 'delivered',
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: MessagesListView(
                messages: messages,
                customerName: 'Test customer',
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('LATEST_MESSAGE'), findsOneWidget);
  });
}
