import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/review_step.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

void main() {
  testWidgets('template review renders unavailable pricing without crashing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewStep(
            templateName: 'Test template',
            whatsappContent: 'Hello {{customerName}}',
            smsContent: 'Hello',
            mediaUrl: '',
            includeSMS: true,
            includeWhatsApp: true,
            whatsappPrice: null,
            smsPricePerSegment: null,
            smsSegments: 1,
            smsEncodingInfo: SMSPricingUtil.classify('Hello'),
            shopName: 'Test shop',
          ),
        ),
      ),
    );

    expect(find.text('WhatsApp pricing unavailable'), findsNWidgets(2));
    expect(find.text('SMS pricing unavailable'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
