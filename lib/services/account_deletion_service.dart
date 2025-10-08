import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AccountDeletionException implements Exception {
  AccountDeletionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AccountDeletionCancelledException extends AccountDeletionException {
  AccountDeletionCancelledException()
      : super('Deletion cancelled by user', code: 'user-cancelled');
}

class AccountDeletionService {
  AccountDeletionService._();

  static final AccountDeletionService instance = AccountDeletionService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> deleteAccount(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AccountDeletionException('No authenticated user found.');
    }

    await _deleteWithRetry(context, allowRetryForRecency: true);
    await _auth.signOut();
  }

  Future<void> _deleteWithRetry(
    BuildContext context, {
    required bool allowRetryForRecency,
  }) async {
    final callable = _functions.httpsCallable('deleteUserAccount');
    try {
      await callable.call();
    } on FirebaseFunctionsException catch (error) {
      final message = error.message ?? 'Failed to delete the account. Please try again later.';
      if (allowRetryForRecency && _isRecentLoginError(error)) {
        await _reauthenticate(context);
        await _deleteWithRetry(context, allowRetryForRecency: false);
        return;
      }
      throw AccountDeletionException(message, code: error.code);
    } catch (error) {
      if (error is AccountDeletionException) rethrow;
      throw AccountDeletionException(error.toString());
    }
  }

  bool _isRecentLoginError(FirebaseFunctionsException error) {
    return error.code == 'failed-precondition' &&
        (error.message?.contains('RECENT_LOGIN_REQUIRED') ?? false);
  }

  Future<void> _reauthenticate(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AccountDeletionException('Reauthentication failed: user not found.');
    }

    final providerIds = user.providerData.map((p) => p.providerId).toList();
    try {
      if (providerIds.contains(PhoneAuthProvider.PROVIDER_ID) && user.phoneNumber != null) {
        await _reauthenticateWithPhone(context, user.phoneNumber!);
        return;
      }

      if (providerIds.contains(EmailAuthProvider.PROVIDER_ID) && user.email != null) {
        await _reauthenticateWithEmail(context, user.email!);
        return;
      }

      throw AccountDeletionException(
        'Unsupported sign-in method for reauthentication. Please sign out and sign back in before deleting your account.',
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(error.toString());
    }
  }

  Future<void> _reauthenticateWithEmail(BuildContext context, String email) async {
    final password = await _promptForPassword(context, email);
    if (password == null || password.isEmpty) {
      throw AccountDeletionCancelledException();
    }

    final credential = EmailAuthProvider.credential(email: email, password: password);
    await _auth.currentUser?.reauthenticateWithCredential(credential);
  }

  Future<void> _reauthenticateWithPhone(BuildContext context, String phoneNumber) async {
    if (kIsWeb) {
      throw AccountDeletionException(
        'Phone reauthentication is not supported on the web. Please sign out and sign back in before deleting your account.',
      );
    }

    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.currentUser?.reauthenticateWithCredential(credential);
          if (!completer.isCompleted) completer.complete();
        } catch (error) {
          if (!completer.isCompleted) {
            completer.completeError(AccountDeletionException(error.toString()));
          }
        }
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!completer.isCompleted) {
          completer.completeError(
            AccountDeletionException(
              error.message ?? 'Failed to verify phone number for reauthentication.',
              code: error.code,
            ),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) async {
        try {
          final smsCode = await _promptForSmsCode(context, phoneNumber);
          if (smsCode == null || smsCode.isEmpty) {
            if (!completer.isCompleted) {
              completer.completeError(AccountDeletionCancelledException());
            }
            return;
          }
          final credential = PhoneAuthProvider.credential(
            verificationId: verificationId,
            smsCode: smsCode,
          );
          await _auth.currentUser?.reauthenticateWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error) {
          if (!completer.isCompleted) {
            completer.completeError(
              error is AccountDeletionException
                  ? error
                  : AccountDeletionException(error.toString()),
            );
          }
        }
      },
      codeAutoRetrievalTimeout: (String _) {},
    );

    await completer.future;
  }

  Future<String?> _promptForPassword(BuildContext context, String email) async {
    final controller = TextEditingController();
    bool obscure = true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Confirm Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the password for $email to continue.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(controller.text.trim()),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<String?> _promptForSmsCode(BuildContext context, String phoneNumber) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Verify Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the code sent to $phoneNumber.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(controller.text.trim()),
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }
}

