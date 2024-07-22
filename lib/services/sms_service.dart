import 'package:pasella/config/remote_config.dart';
import 'package:twilio_flutter/twilio_flutter.dart';

class SMSService {
  final TwilioFlutter twilioFlutter;

  SMSService._(this.twilioFlutter);

  static SMSService create() {
    final remoteConfigService = RemoteConfigService.createInstance();

    final twilioFlutter = TwilioFlutter(
      accountSid: remoteConfigService.getString('TWILIO_ACCOUNT_SID')!,
      authToken: remoteConfigService.getString('TWILIO_AUTH_TOKEN')!,
      twilioNumber: remoteConfigService.getString('TWILIO_NUMBER')!,
    );

    return SMSService._(twilioFlutter);
  }

  Future<void> sendSMS(String phoneNumber, String message) async {
    await twilioFlutter.sendSMS(
      toNumber: phoneNumber,
      messageBody: message,
    );
  }
}
