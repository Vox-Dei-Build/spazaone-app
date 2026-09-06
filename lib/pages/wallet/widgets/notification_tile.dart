import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/wallet/widgets/wallet_activity_tile.dart';
import 'package:pasella/utils/currency_util.dart';

class NotificationTile extends StatelessWidget {
  final String message;
  final String templateType;
  final num messageCost;
  final String phone;
  final DateTime date;

  const NotificationTile({
    super.key,
    required this.message,
    required this.templateType,
    required this.messageCost,
    required this.phone,
    required this.date,
  });

  @override
  Widget build(BuildContext context) => WalletActivityTile(
        icon: Icon(
          templateType == 'whatsapp'
              ? FontAwesomeIcons.whatsapp
              : Icons.sms_outlined,
          color: templateType == 'whatsapp'
              ? SpazaColors.action
              : SpazaColors.heading,
          size: 22,
        ),
        title:
            templateType == 'whatsapp' ? 'WhatsApp messages' : 'SMS messages',
        subtitle: '${DateFormat.yMMMd().format(date)} · $phone',
        amount: '-${CurrencyUtil.format(messageCost.toDouble())}',
        onTap: () => _showMessageDetails(context),
      );

  void _showMessageDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Message details',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                _detail(context, 'Recipient', phone),
                _detail(context, 'Date sent', DateFormat.yMMMd().format(date)),
                _detail(context, 'Message cost',
                    '-${CurrencyUtil.format(messageCost.toDouble())}'),
                const SizedBox(height: 8),
                Text('Message content',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SpazaColors.subtle,
                    borderRadius: BorderRadius.circular(SpazaRadius.control),
                  ),
                  child: Text(message,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
