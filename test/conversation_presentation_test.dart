import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/conversation/conversation_presentation.dart';
import 'package:pasella/pages/contact/connect/widgets/message_card.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';
import 'package:pasella/pages/contact/view_model/connect_management_view_model.dart';
import 'package:pasella/config/size_config.dart';

void main() {
  test('normalizes WhatsApp options without retaining action values', () {
    final presentation = ConversationPresentationV1.fromPayload({
      'type': 'choice',
      'text': 'How would you like to pay?',
      'options': [
        {'label': 'Pay online', 'value': 'execute:payment:secret'},
      ],
    });
    expect(presentation.type, ConversationPresentationType.choices);
    expect(presentation.options.single.label, 'Pay online');
    expect(presentation.options.single.description, isNull);
  });

  test('normalizes carousel images, copy and visible action labels', () {
    final presentation = ConversationPresentationV1.fromPayload({
      'type': 'carousel',
      'text': 'Products',
      'items': [
        {
          'title': 'Bread',
          'subtitle': 'Fresh loaf',
          'imageUrl': 'https://example.com/bread.jpg',
          'actions': [
            {'label': 'Choose', 'value': 'product:123'},
          ],
        },
      ],
    });
    expect(presentation.cards.single.title, 'Bread');
    expect(presentation.cards.single.actions.single.label, 'Choose');
  });

  test('normalizes lists, media, location and unknown payloads safely', () {
    final list = ConversationPresentationV1.fromPayload({
      'type': 'list',
      'title': 'Choose a category',
      'sections': [
        {
          'title': 'Popular',
          'rows': [
            {'title': 'Bread', 'value': 'secret:bread'},
          ],
        },
      ],
    });
    expect(list.type, ConversationPresentationType.list);
    expect(list.options.single.label, 'Bread');
    expect(list.options.single.description, 'Popular');

    for (final type in ['audio', 'video', 'document']) {
      final media = ConversationPresentationV1.fromPayload({
        'type': type,
        'mediaUrl': 'https://example.com/media',
        'fileName': 'receipt.pdf',
      });
      expect(media.mediaUrl, 'https://example.com/media');
    }
    final location = ConversationPresentationV1.fromPayload({
      'type': 'location',
      'latitude': -26.2041,
      'longitude': 28.0473,
      'address': 'Johannesburg',
    });
    expect(location.text, 'Johannesburg');

    final unknown = ConversationPresentationV1.fromPayload(
      {'type': 'provider-secret-action'},
    );
    expect(unknown.type, ConversationPresentationType.unsupported);
  });

  test('rich presentation wins independently of delivery source', () {
    final twilio = <String, dynamic>{
      'message': 'Choose one',
      'source': 'twilio-outbound',
      'status': 'read',
    };
    final botpress = <String, dynamic>{
      'message': 'Choose one',
      'source': 'botpress',
      'presentation': {
        'schemaVersion': 1,
        'type': 'choices',
        'text': 'Choose one',
        'options': [
          {'label': 'Cash'},
          {'label': 'Pay online'},
        ],
      },
    };
    final richest = selectRichestConversationPresentation(twilio, botpress);
    expect(richest.type, ConversationPresentationType.choices);
    expect(richest.options, hasLength(2));
  });

  test('keeps only a safe quoted-message reference', () {
    expect(
      ConversationPresentationV1.fromPayload({
        'type': 'text',
        'text': 'Cash',
        'replyToId': 'message_123:question',
      }).replyToId,
      'message_123:question',
    );
    expect(
      ConversationPresentationV1.fromPayload({
        'type': 'text',
        'text': 'Cash',
        'replyToId': 'execute payment now',
      }).replyToId,
      isNull,
    );
  });

  testWidgets('renders formatting and static reply choices', (tester) async {
    final message = <String, dynamic>{
      'message': 'Choose one',
      'dateSent': DateTime(2026, 8, 13, 12),
      'direction': 'outbound',
      'isWhatsApp': true,
      'presentation': {
        'schemaVersion': 1,
        'type': 'choices',
        'text': 'Choose one',
        'options': [
          {'label': 'Cash'},
          {'label': 'Pay online'},
        ],
      },
    };
    expect(
      ConversationPresentationV1.fromMessage(message).options.length,
      2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              SizeConfig().init(context);
              return Column(
                children: [
                  const WhatsAppFormattedText(
                    '*Bold* _italics_ ~done~ ```code```',
                  ),
                  MessageCard(message, customerName: 'Naledi'),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('Bold'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Pay online'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('rejects non-HTTPS media from display presentation', () {
    final presentation = ConversationPresentationV1.fromPayload({
      'type': 'image',
      'imageUrl': 'file:///private/raw-audio.aiff',
    });
    expect(presentation.mediaUrl, isNull);
  });

  testWidgets('resolves and renders quoted reply context', (tester) async {
    final sent = DateTime(2026, 8, 13, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessagesListView(
            customerName: 'Naledi',
            messages: [
              {
                'id': 'question-1',
                'message': 'How would you like to pay?',
                'dateSent': sent,
                'direction': 'outbound',
                'isWhatsApp': true,
              },
              {
                'id': 'reply-1',
                'replyTo': 'question-1',
                'message': 'Cash',
                'dateSent': sent.add(const Duration(minutes: 1)),
                'direction': 'inbound',
                'isWhatsApp': true,
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('How would you like to pay?'), findsNWidgets(2));
    expect(find.text('Cash'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
