import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';

void main() {
  group('phoneVerificationErrorMessage', () {
    test('does not expose Firebase backend configuration details', () {
      final error = FirebaseAuthException(
        code: 'app-not-authorized',
        message: 'Package, SHA-1, SHA-256, Firebase Console, '
            'play_integrity_token',
      );

      final message = phoneVerificationErrorMessage(error);

      expect(
        message,
        "We couldn't send the verification code. Please try again.",
      );
      expect(message, isNot(contains('Firebase')));
      expect(message, isNot(contains('SHA-1')));
      expect(message, isNot(contains('play_integrity_token')));
    });

    test('provides actionable copy for known recoverable failures', () {
      expect(
        phoneVerificationErrorMessage(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        contains('offline'),
      );
      expect(
        phoneVerificationErrorMessage(
          FirebaseAuthException(code: 'too-many-requests'),
        ),
        contains('wait'),
      );
      expect(
        phoneVerificationErrorMessage(
          FirebaseAuthException(code: 'invalid-phone-number'),
        ),
        contains('South African mobile number'),
      );
    });
  });
}
