import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/widgets/private_region.dart';

typedef OtpVerifyCallback = Future<bool> Function(String code);
typedef OtpResendCallback = Future<void> Function();
typedef OtpCancelCallback = Future<void> Function();

Future<bool> showOtpCodeDialog(
  BuildContext context, {
  required String? maskedNumber,
  required OtpVerifyCallback onVerify,
  OtpResendCallback? onResend,
  OtpCancelCallback? onCancel,
  bool enableAutosubmit = false,
  bool enableResend = false,
  Duration resendDelay = const Duration(seconds: 30),
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OtpCodeDialog(
      maskedNumber: maskedNumber,
      onVerify: onVerify,
      onResend: onResend,
      onCancel: onCancel,
      enableAutosubmit: enableAutosubmit,
      enableResend: enableResend,
      resendDelay: resendDelay,
    ),
  );
  return result ?? false;
}

class OtpCodeDialog extends StatefulWidget {
  const OtpCodeDialog({
    super.key,
    required this.maskedNumber,
    required this.onVerify,
    this.onResend,
    this.onCancel,
    this.enableAutosubmit = false,
    this.enableResend = false,
    this.resendDelay = const Duration(seconds: 30),
  });

  final String? maskedNumber;
  final OtpVerifyCallback onVerify;
  final OtpResendCallback? onResend;
  final OtpCancelCallback? onCancel;
  final bool enableAutosubmit;
  final bool enableResend;
  final Duration resendDelay;

  @override
  State<OtpCodeDialog> createState() => _OtpCodeDialogState();
}

class _OtpCodeDialogState extends State<OtpCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _resendTimer;
  bool _verifying = false;
  bool _resending = false;
  String? _errorText;
  int _secondsUntilResend = 0;
  String? _autoSubmittedCode;

  @override
  void initState() {
    super.initState();
    if (widget.enableResend) {
      _startResendTimer();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _secondsUntilResend = widget.resendDelay.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsUntilResend <= 1) {
        timer.cancel();
        setState(() => _secondsUntilResend = 0);
        return;
      }
      setState(() => _secondsUntilResend -= 1);
    });
  }

  Future<void> _verify({required bool automatic}) async {
    if (_verifying) return;
    final code = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _errorText = 'Enter the 6-digit SMS code');
      return;
    }
    if (automatic && _autoSubmittedCode == code) return;
    if (automatic) _autoSubmittedCode = code;

    setState(() {
      _verifying = true;
      _errorText = null;
    });
    final ok = await widget.onVerify(code);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _verifying = false;
      _errorText = "That code didn't work. Check the SMS and try again.";
    });
  }

  Future<void> _resend() async {
    if (_resending || _secondsUntilResend > 0 || widget.onResend == null) {
      return;
    }
    setState(() {
      _resending = true;
      _errorText = null;
      _autoSubmittedCode = null;
      _controller.clear();
    });
    await widget.onResend!();
    if (!mounted) return;
    setState(() => _resending = false);
    _startResendTimer();
  }

  Future<void> _cancel() async {
    if (_verifying || _resending) return;
    await widget.onCancel?.call();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  void _onCodeChanged(String value) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
    final code = value.replaceAll(RegExp(r'\D'), '');
    if (widget.enableAutosubmit && code.length == 6) {
      unawaited(_verify(automatic: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your 6-digit code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.maskedNumber != null
                  ? 'We just sent an SMS to ${widget.maskedNumber}. '
                      'Enter the code to continue.'
                  : 'We just sent you an SMS. Enter the code to continue.',
              style: TextStyle(color: Colors.grey[800], height: 1.3),
            ),
            const SizedBox(height: 14),
            PrivateRegion(
              child: TextField(
                controller: _controller,
                enabled: !_verifying && !_resending,
                onChanged: _onCodeChanged,
                decoration: InputDecoration(
                  hintText: '6-digit SMS code',
                  errorText: _errorText,
                  helperText: widget.enableResend
                      ? _resendHelperText
                      : "Code didn't arrive? Wait 30 seconds, then tap "
                          'Cancel and try again.',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _verify(automatic: false),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_verifying || _resending) ? null : _cancel,
          child: const Text('Cancel'),
        ),
        if (widget.enableResend)
          TextButton(
            onPressed: (_secondsUntilResend == 0 && !_verifying && !_resending)
                ? _resend
                : null,
            child: Text(_resending ? 'Sending...' : 'Resend'),
          ),
        FilledButton(
          onPressed: (_verifying || _resending)
              ? null
              : () => _verify(automatic: false),
          child: Text(_verifying ? 'Verifying...' : 'Verify'),
        ),
      ],
    );
  }

  String get _resendHelperText {
    if (_secondsUntilResend > 0) {
      return 'Code taking long? You can resend in ${_secondsUntilResend}s.';
    }
    return 'Code taking long? Tap Resend to send a new SMS.';
  }
}
