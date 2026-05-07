import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Canonical lifecycle states for a WhatsApp template's approval, mapped from
/// the loosely-typed `channels.whatsapp.approvalStatus` string written by the
/// backend (see `submitWhatsAppTemplate` and `checkTwilioApprovalStatuses`).
enum TemplateStatus {
  /// Newly created, not yet submitted to Twilio.
  draft,

  /// Successfully submitted to Twilio, awaiting WhatsApp review.
  pending,

  /// WhatsApp approved — usable in promotions.
  approved,

  /// WhatsApp rejected — user must fix and resubmit.
  rejected,

  /// Backend submission to Twilio failed (e.g. network/auth) — user can retry.
  submissionFailed,

  /// Status string we don't recognise — show raw value, treat as pending.
  unknown,
}

extension TemplateStatusX on TemplateStatus {
  String get label {
    switch (this) {
      case TemplateStatus.draft:
        return 'Draft';
      case TemplateStatus.pending:
        return 'Pending';
      case TemplateStatus.approved:
        return 'Approved';
      case TemplateStatus.rejected:
        return 'Rejected';
      case TemplateStatus.submissionFailed:
        return 'Submission failed';
      case TemplateStatus.unknown:
        return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case TemplateStatus.draft:
        return Colors.blueGrey;
      case TemplateStatus.pending:
        return Colors.amber.shade700;
      case TemplateStatus.approved:
        return Colors.green;
      case TemplateStatus.rejected:
        return Colors.red;
      case TemplateStatus.submissionFailed:
        return Colors.deepOrange;
      case TemplateStatus.unknown:
        return Colors.grey;
    }
  }

  IconData get icon {
    switch (this) {
      case TemplateStatus.draft:
        return Icons.edit_note;
      case TemplateStatus.pending:
        return Icons.hourglass_top;
      case TemplateStatus.approved:
        return Icons.check_circle;
      case TemplateStatus.rejected:
        return Icons.cancel;
      case TemplateStatus.submissionFailed:
        return Icons.warning_amber_rounded;
      case TemplateStatus.unknown:
        return Icons.help_outline;
    }
  }

  /// Whether the template can be selected for sending a promotion.
  bool get isUsable => this == TemplateStatus.approved;
}

/// Reads the canonical [TemplateStatus] from a Firestore template document.
///
/// Honours the legacy `approved == true` boolean for backwards compatibility
/// with templates created before the `approvalStatus` string was introduced.
TemplateStatus templateStatusOf(Map<String, dynamic> template) {
  final wa = template['channels']?['whatsapp'] as Map<String, dynamic>?;
  if (wa == null) return TemplateStatus.unknown;

  final raw = (wa['approvalStatus'] as String?)?.toLowerCase();

  if (raw == 'approved' || wa['approved'] == true) {
    return TemplateStatus.approved;
  }
  switch (raw) {
    case 'rejected':
      return TemplateStatus.rejected;
    case 'submission_failed':
      return TemplateStatus.submissionFailed;
    case 'pending':
    case 'submitted':
      return TemplateStatus.pending;
    case null:
    case '':
      return TemplateStatus.draft;
    default:
      return TemplateStatus.unknown;
  }
}

/// Convenience: extracts the rejection / submission-error reason string, if any.
String? templateFailureReason(Map<String, dynamic> template) {
  final wa = template['channels']?['whatsapp'] as Map<String, dynamic>?;
  if (wa == null) return null;
  final reason = (wa['rejectionReason'] ?? wa['submissionError']) as String?;
  if (reason == null || reason.trim().isEmpty) return null;
  return reason;
}

/// Returns a Firestore [Timestamp] for when the template was submitted, if
/// available. Falls back to `createdAt` for older docs.
DateTime? templateSubmittedAt(Map<String, dynamic> template) {
  final wa = template['channels']?['whatsapp'] as Map<String, dynamic>?;
  final ts = (wa?['submittedAt'] ?? template['createdAt']) as Timestamp?;
  return ts?.toDate();
}

/// Tiny human-friendly relative time formatter ("3 minutes ago", "2 hours
/// ago", "yesterday"). Kept inline rather than pulled in as a dep because
/// our needs are minimal and predictable.
String relativeTime(DateTime when, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 30) {
    final w = (diff.inDays / 7).floor();
    return '$w ${w == 1 ? 'week' : 'weeks'} ago';
  }
  final months = (diff.inDays / 30).floor();
  if (months < 12) return '$months ${months == 1 ? 'month' : 'months'} ago';
  final years = (diff.inDays / 365).floor();
  return '$years ${years == 1 ? 'year' : 'years'} ago';
}
