import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
import 'package:pasella/pages/contact/connect/widgets/message_card.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';
import 'package:pasella/pages/contact/view_model/connect_management_view_model.dart';

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

  testWidgets('long conversations parse history once and build visible rows',
      (tester) async {
    final now = DateTime(2026, 8, 14, 10);
    final messages = List<Map<String, dynamic>>.generate(
        800,
        (index) => {
              'id': 'message-$index',
              'message': 'Message $index',
              'dateSent': now.add(Duration(minutes: index)),
              'direction': index.isEven ? 'outbound' : 'inbound',
              'isWhatsApp': true,
            });
    var parseCount = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            SizeConfig().init(context);
            return Scaffold(
              body: MessagesListView(
                messages: messages,
                customerName: 'Test customer',
                presentationParser: (message) {
                  parseCount++;
                  return ConversationPresentationV1.fromMessage(message);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(parseCount, messages.length);
    expect(find.byType(MessageCard).evaluate().length, lessThan(40));

    rebuild(() {});
    await tester.pump();
    expect(parseCount, messages.length);
  });

  test('indexed message merge does not scan unrelated conversation history',
      () {
    final now = DateTime(2026, 8, 14);
    final messages = List<Map<String, dynamic>>.generate(
        5000,
        (index) => {
              'id': 'message-$index',
              'body': 'unique-$index',
              'date': now.add(Duration(minutes: index)),
              'version': 1,
            })
      ..add({
        'id': 'message-2500',
        'body': 'updated',
        'date': now.add(const Duration(minutes: 2500)),
        'version': 2,
      });
    var renderedComparisons = 0;

    final result = dedupeByIdAndTimeBucket<Map<String, dynamic>>(
      messages,
      idOf: (message) => message['id'] as String,
      renderedSignatureOf: (message) => message['body'] as String,
      dateOf: (message) => message['date'] as DateTime,
      isRenderedDuplicate: (existing, next) {
        renderedComparisons++;
        return existing['body'] == next['body'];
      },
      merge: (existing, next) => {...existing, ...next},
    );

    expect(result, hasLength(5000));
    expect(result[2500]['version'], 2);
    expect(renderedComparisons, 0);
  });
}
