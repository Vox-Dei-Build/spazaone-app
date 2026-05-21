import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/utils/phone_util.dart';

/// PAS-WA-V1: process-wide cache of `successfulWhatsAppNumbers`
/// lookups, used by the ledger/customer list to render a channel
/// capability indicator on each tile without firing one Firestore
/// read per row.
///
/// Capability tri-state (mirrors `MessageChannelExpectation` so the
/// UI and the dispatcher tell the same story to the merchant):
///
/// * `true`  → number is known on WhatsApp (last successful WA send
///             on file) → tile shows "WhatsApp" badge.
/// * `false` → number is known **not** on WhatsApp AND the cache
///             entry is fresh (≤ 30 days). Tile shows "SMS" badge.
/// * `null`  → no record OR the negative record is stale (> 30 days,
///             dispatcher will retry WhatsApp). Tile shows a neutral
///             "phone" badge — we deliberately do not pretend
///             certainty here.
///
/// The negative-fresh-vs-stale distinction matches
/// `MessagingNotificationService.resolveExpectedChannel` exactly so
/// the cost-confirmation sheet, the customer detail header, and the
/// ledger tile cannot disagree about the same number.
class WhatsAppCapabilityCache extends ChangeNotifier {
  WhatsAppCapabilityCache._();
  static final WhatsAppCapabilityCache instance = WhatsAppCapabilityCache._();

  static const Duration _staleAfter = Duration(days: 30);
  // Firestore `whereIn` allows up to 30 elements per query.
  static const int _chunkSize = 30;

  final Map<String, bool?> _byNormalizedNumber = <String, bool?>{};
  final Set<String> _inFlight = <String>{};

  /// Look up a single number from the cache. Returns `null` for both
  /// "not loaded yet" and "loaded as unknown" — callers that need to
  /// distinguish should check [hasEntry].
  bool? capabilityFor(String? rawNumber) {
    if (rawNumber == null || rawNumber.isEmpty) return null;
    final normalized = normalizePhoneNumber(rawNumber);
    if (normalized.isEmpty) return null;
    return _byNormalizedNumber[normalized];
  }

  bool hasEntry(String? rawNumber) {
    if (rawNumber == null || rawNumber.isEmpty) return false;
    final normalized = normalizePhoneNumber(rawNumber);
    if (normalized.isEmpty) return false;
    return _byNormalizedNumber.containsKey(normalized);
  }

  /// Bulk-load capability for the supplied raw numbers. Already-cached
  /// numbers are skipped, so calling this every time the customer
  /// stream emits is cheap. Triggers a single `notifyListeners()` at
  /// the end so the ledger rebuilds once, not per chunk.
  Future<void> primeFor(Iterable<String?> rawNumbers) async {
    final normalized = <String>{};
    for (final raw in rawNumbers) {
      if (raw == null || raw.isEmpty) continue;
      final n = normalizePhoneNumber(raw);
      if (n.isEmpty) continue;
      if (_byNormalizedNumber.containsKey(n)) continue;
      if (_inFlight.contains(n)) continue;
      normalized.add(n);
    }
    if (normalized.isEmpty) return;

    _inFlight.addAll(normalized);
    final list = normalized.toList();
    final cutoff = DateTime.now().subtract(_staleAfter);

    try {
      for (var i = 0; i < list.length; i += _chunkSize) {
        final end = (i + _chunkSize > list.length) ? list.length : i + _chunkSize;
        final chunk = list.sublist(i, end);
        final snap = await FirebaseFirestore.instance
            .collection('successfulWhatsAppNumbers')
            .where('phoneNumber', whereIn: chunk)
            .get();

        // Seed every requested number with `null` (unknown) first, so
        // numbers without a record don't fall back to a stale "SMS"
        // verdict from a sibling.
        for (final n in chunk) {
          _byNormalizedNumber.putIfAbsent(n, () => null);
        }

        for (final doc in snap.docs) {
          final data = doc.data();
          final phone = data['phoneNumber'] as String?;
          if (phone == null) continue;
          final hasWa = data['hasWhatsApp'] as bool? ?? false;
          final lastChecked = (data['lastChecked'] as Timestamp?)?.toDate();
          if (hasWa) {
            _byNormalizedNumber[phone] = true;
          } else if (lastChecked != null && lastChecked.isAfter(cutoff)) {
            // Fresh negative — trust it.
            _byNormalizedNumber[phone] = false;
          } else {
            // Stale negative → unknown; dispatcher will retry WA.
            _byNormalizedNumber[phone] = null;
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('WhatsAppCapabilityCache.primeFor failed: $e');
    } finally {
      _inFlight.removeAll(normalized);
    }
  }

  /// Test/debug-only reset hook.
  @visibleForTesting
  void reset() {
    _byNormalizedNumber.clear();
    _inFlight.clear();
  }
}
