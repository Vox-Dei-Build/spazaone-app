import 'package:flutter/material.dart';

/// Visible delivery state for a WhatsApp message sent from an order action.
///
/// Mirrors the carrier states polled from Twilio plus the two app-side states
/// we need so merchants can tell, at a glance, whether the WhatsApp send
/// happened and whether the customer has replied.
enum WhatsAppDeliveryState {
  unsent, // no phone number / never attempted
  queued, // submission in flight to Twilio
  sent, // accepted by Twilio
  delivered, // confirmed by carrier
  failed, // rejected by Twilio or carrier
  replied, // inbound message tied to this send (bot or human)
}

class WhatsAppDeliveryPill extends StatelessWidget {
  const WhatsAppDeliveryPill(
      {super.key, required this.state, this.compact = false});

  final WhatsAppDeliveryState state;
  final bool compact;

  static WhatsAppDeliveryState fromMap(Map? lastMessage) {
    if (lastMessage == null || lastMessage.isEmpty) {
      return WhatsAppDeliveryState.unsent;
    }
    final channel = (lastMessage['channel'] ?? '').toString().toLowerCase();
    if (channel.isNotEmpty && channel != 'whatsapp') {
      // We only render a WhatsApp pill for the WhatsApp channel. Other channels
      // can be added later; until then, hide gracefully.
      return WhatsAppDeliveryState.unsent;
    }
    final status = (lastMessage['status'] ?? '').toString().toLowerCase();
    final repliedAt = lastMessage['repliedAt'];
    if (repliedAt != null) return WhatsAppDeliveryState.replied;
    switch (status) {
      case 'queued':
        return WhatsAppDeliveryState.queued;
      case 'sent':
        return WhatsAppDeliveryState.sent;
      case 'delivered':
      case 'read':
        return WhatsAppDeliveryState.delivered;
      case 'failed':
      case 'undelivered':
      case 'canceled':
        return WhatsAppDeliveryState.failed;
      case 'unsent':
        return WhatsAppDeliveryState.unsent;
    }
    return WhatsAppDeliveryState.unsent;
  }

  static String labelFor(WhatsAppDeliveryState s) {
    switch (s) {
      case WhatsAppDeliveryState.unsent:
        return 'WhatsApp · not sent';
      case WhatsAppDeliveryState.queued:
        return 'WhatsApp · queued';
      case WhatsAppDeliveryState.sent:
        return 'WhatsApp · sent';
      case WhatsAppDeliveryState.delivered:
        return 'WhatsApp · delivered';
      case WhatsAppDeliveryState.failed:
        return 'WhatsApp · failed';
      case WhatsAppDeliveryState.replied:
        return 'WhatsApp · replied';
    }
  }

  static Color _colorFor(BuildContext context, WhatsAppDeliveryState s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case WhatsAppDeliveryState.unsent:
        return Colors.grey.shade500;
      case WhatsAppDeliveryState.queued:
        return Colors.blueGrey.shade400;
      case WhatsAppDeliveryState.sent:
        // WhatsApp brand green.
        return const Color(0xFF25D366);
      case WhatsAppDeliveryState.delivered:
        return const Color(0xFF128C7E);
      case WhatsAppDeliveryState.failed:
        return cs.error;
      case WhatsAppDeliveryState.replied:
        // Reuse the primary "verified/trust" colour to imply two-way contact.
        return cs.primary;
    }
  }

  static IconData _iconFor(WhatsAppDeliveryState s) {
    switch (s) {
      case WhatsAppDeliveryState.unsent:
        return Icons.message_outlined;
      case WhatsAppDeliveryState.queued:
        return Icons.schedule;
      case WhatsAppDeliveryState.sent:
        return Icons.check;
      case WhatsAppDeliveryState.delivered:
        return Icons.done_all;
      case WhatsAppDeliveryState.failed:
        return Icons.error_outline;
      case WhatsAppDeliveryState.replied:
        return Icons.reply;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(context, state);
    final icon = _iconFor(state);
    final label = labelFor(state);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: Colors.white),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
