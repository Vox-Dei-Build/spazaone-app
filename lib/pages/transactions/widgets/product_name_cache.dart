// Batched product-name resolver for the Pay Later transactions list.
//
// Background:
//   Each transaction stores a `products: Map<productId, qty>`. The original
//   `TransactionCard` displayed the first product name by issuing its own
//   `users/{uid}/products/{productId}.get()` inside the build method — N+1
//   Firestore reads per visible bubble. On a customer with 50 transactions
//   that is 50 document reads on every scroll into view, plus flicker as
//   each bubble's `FutureBuilder` resolved independently.
//
// This resolver collects all unique product IDs from a list of transactions
// and fetches their names with chunked `whereIn` queries (10 IDs per chunk
// to stay safely under historical Firestore limits). The result is exposed
// as a `Map<productId, name>` for synchronous lookup inside each bubble.
//
// Cache lifetime is per-list-instance: when the merchant scrolls into a
// customer profile, the names load once and then every subsequent stream
// snapshot reuses them. New IDs introduced by a new transaction are picked
// up on the next call to [resolve].

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ProductNameCache extends ChangeNotifier {
  final String userId;
  final Map<String, String> _names = {};
  final Set<String> _inFlight = {};
  bool _disposed = false;

  ProductNameCache({required this.userId});

  /// Synchronous accessor used by bubbles. Returns null for IDs we have not
  /// resolved yet; the bubble then shows a neutral placeholder until the
  /// resolver finishes and `notifyListeners()` triggers a rebuild.
  String? nameFor(String productId) => _names[productId];

  Map<String, String> get names => Map.unmodifiable(_names);

  /// Kick off batched lookups for any product IDs present in [transactions]
  /// that we haven't seen before. Safe to call on every stream snapshot —
  /// already-resolved and in-flight IDs are skipped.
  Future<void> resolveFromTransactions(
      List<Map<String, dynamic>> transactions) async {
    if (userId.isEmpty) return;
    final unseen = <String>{};
    for (final t in transactions) {
      final products = t['products'];
      if (products is Map) {
        for (final id in products.keys) {
          if (id is! String) continue;
          if (id.isEmpty) continue;
          if (_names.containsKey(id)) continue;
          if (_inFlight.contains(id)) continue;
          unseen.add(id);
        }
      }
    }
    if (unseen.isEmpty) return;
    _inFlight.addAll(unseen);

    // Chunk by 10 — the historical whereIn cap. Each chunk is one round-trip.
    final chunks = <List<String>>[];
    final ids = unseen.toList();
    for (var i = 0; i < ids.length; i += 10) {
      chunks.add(ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10));
    }
    try {
      for (final chunk in chunks) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('products')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final name = (data['name'] as String?) ?? 'Product';
          _names[doc.id] = name;
        }
        // Any IDs in the chunk that didn't come back (deleted product?)
        // get a stable fallback so we don't refetch them forever.
        for (final id in chunk) {
          _names.putIfAbsent(id, () => 'Product');
        }
      }
    } catch (_) {
      // Network blip — drop in-flight markers so a later call can retry.
      _inFlight.removeAll(unseen);
      rethrow;
    } finally {
      _inFlight.removeAll(unseen);
    }

    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
