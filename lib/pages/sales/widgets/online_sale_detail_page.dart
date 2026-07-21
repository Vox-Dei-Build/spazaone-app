// lib/pages/sales/widgets/online_sale_detail_page.dart
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/function_endpoints.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/status_pill.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_avatar.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

class OnlineSaleDetailPage extends StatefulWidget {
  final String orderId;
  const OnlineSaleDetailPage({super.key, required this.orderId});

  @override
  State<OnlineSaleDetailPage> createState() => _OnlineSaleDetailPageState();
}

class _OnlineSaleDetailPageState extends State<OnlineSaleDetailPage> {
  late Future<Map<String, dynamic>?> _future;

  Uri get _endpoint => FunctionEndpoints.https('getOnlineSalesFromLedger');

  @override
  void initState() {
    super.initState();
    _future = _fetchLedgerSale(widget.orderId);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetchLedgerSale(widget.orderId));
    await _future;
  }

  /// Fetch **one** ledger sale matching [orderId].
  /// Tries a direct-filter call (if CF supports it), else falls back to
  /// fetching a page then filtering locally.
  Future<Map<String, dynamic>?> _fetchLedgerSale(String orderId) async {
    final uid = StoreSession.instance.storeId;
    if (uid.isEmpty) throw Exception('Not signed in');

    String? appCheck;
    String? idToken;
    try {
      appCheck = await FirebaseAppCheck.instance.getToken();
    } catch (_) {}
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    // 1) Try direct lookup by orderId (if backend supports it)
    final direct = await _postForSingleSale(
      body: {'merchantId': uid, 'limit': 1, 'orderId': orderId},
      appCheck: appCheck,
      idToken: idToken,
      allow404: true,
    );
    if (direct != null) {
      debugPrint('[detail] Direct hit for $orderId');
      return direct;
    }

    // 2) Fallback: pull a page and filter locally
    final fall = await _postForList(
      body: {'merchantId': uid, 'limit': 500},
      appCheck: appCheck,
      idToken: idToken,
    );
    if (fall == null) return null;

    final sales = fall;
    final hit = sales.cast<Map>().cast<Map<String, dynamic>>().where((m) {
      final id = (m['id'] ?? '').toString();
      return id == orderId;
    }).toList();

    if (hit.isEmpty) {
      debugPrint('[detail] No sale found for $orderId in fallback page.');
      return null;
    }

    debugPrint('[detail] Fallback matched sale for $orderId');
    return hit.first;
  }

  /// Posts to the CF and returns **the first sale object** if available.
  Future<Map<String, dynamic>?> _postForSingleSale({
    required Map<String, dynamic> body,
    String? appCheck,
    String? idToken,
    bool allow404 = false,
  }) async {
    final resp = await http.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        if (appCheck != null) 'X-Firebase-AppCheck': appCheck,
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode == 404 && allow404) return null;
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map &&
        decoded['sales'] is List &&
        decoded['sales'].isNotEmpty) {
      // ✅ return the single sale map
      return Map<String, dynamic>.from((decoded['sales'] as List).first as Map);
    }

    // If it's 200 but empty, return null so caller can fallback.
    return null;
  }

  /// Posts to the CF and returns the **list of sales** (possibly empty).
  Future<List<Map<String, dynamic>>?> _postForList({
    required Map<String, dynamic> body,
    String? appCheck,
    String? idToken,
  }) async {
    final resp = await http.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        if (appCheck != null) 'X-Firebase-AppCheck': appCheck,
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['sales'] is List) {
      return (decoded['sales'] as List)
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Map) {
      final s = v['seconds'] ?? v['_seconds'];
      final ns =
          v['nanoseconds'] ?? v['_nanoseconds'] ?? v['nanos'] ?? v['_nanos'];
      if (s is num) {
        final ms = (s * 1000).toInt() + ((ns is num) ? (ns ~/ 1000000) : 0);
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      }
    }
    if (v is String) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.isUtc ? dt.toLocal() : dt;
    }
    return null;
  }

  num _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final money =
        NumberFormat.currency(locale: 'en_ZA', symbol: 'R', decimalDigits: 2);

    return Scaffold(
      appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            if (snap.hasError) {
              return _Error(message: '${snap.error}');
            }

            final raw = snap.data;
            if (raw == null || raw.isEmpty) {
              return const _Empty();
            }

            // --- Map ledger fields (exactly like list) ---
            final id = (raw['id'] ?? widget.orderId).toString();
            final reference = (raw['reference'] ?? '').toString();

            final statusRaw =
                (raw['status'] ?? 'paid').toString().toLowerCase();
            final (pillColor, statusText) = _statusColorAndText(statusRaw);

            final created = _parseDate(raw['createdAt']);
            final ledgerCreated = _parseDate(raw['ledgerCreatedAt']);
            final shownDate = created ?? ledgerCreated;

            final orderTotal = (_asNum(raw['orderTotal'])).toDouble();
            final paid = (_asNum(raw['amountPaid'])).toDouble();
            final feesIncl = (_asNum(raw['feeInclVat'])).toDouble();
            final net = (_asNum(raw['netAmount'])).toDouble();

            final method = ((raw['method'] ?? raw['channel']) ?? '')
                .toString()
                .toUpperCase();
            final itemsCount = (_asNum(raw['itemsCount'])).toInt();

            final padH = SizeConfig.imageSizeMultiplier * 3;
            final padV = SizeConfig.heightMultiplier * 1.2;

            return ListView(
              padding: EdgeInsets.fromLTRB(padH, padV, padH, padV * 2),
              children: [
                // HERO
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            OrderAvatar(color: pillColor),
                            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                            Expanded(
                              child: Text(
                                money.format(orderTotal),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 3.0,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            StatusPill(text: statusText, color: pillColor),
                          ],
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 1.0),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _pill(context, method.isEmpty ? 'ONLINE' : method),
                            if (itemsCount > 0)
                              _pill(context, '$itemsCount items'),
                            if (reference.isNotEmpty)
                              _pill(context, 'Ref: $reference'),
                            _pill(context, 'ID: $id'),
                          ],
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 1.2),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _fmtDate(shownDate) ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 1.0),

                // BREAKDOWN
                Row(
                  children: [
                    Expanded(
                        child: _kvCard(
                            context, 'Order', money.format(orderTotal))),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                    Expanded(
                        child: _kvCard(context, 'Paid', money.format(paid))),
                  ],
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1.0),
                Row(
                  children: [
                    Expanded(
                        child: _kvCard(context, 'Fees (incl VAT)',
                            money.format(feesIncl))),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                    Expanded(child: _kvCard(context, 'Net', money.format(net))),
                  ],
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 1.2),

                // TIMELINE
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Timeline',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: SizeConfig.heightMultiplier * 1.0),
                        _timelineRow(
                          context,
                          Icons.bolt,
                          'Created',
                          _fmtDate(created) ?? '—',
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 0.8),
                        _timelineRow(
                          context,
                          Icons.receipt_long,
                          'Ledger Created',
                          _fmtDate(ledgerCreated) ?? '—',
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 1.2),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- UI helpers ----

  static (Color, String) _statusColorAndText(String raw) {
    final s = raw.toLowerCase();
    if (s == 'paid') return (Colors.green.shade600, 'Paid');
    if (s == 'collected') return (Colors.teal.shade600, 'Collected');
    if (s == 'pending') return (Colors.orange.shade700, 'Pending');
    if (s == 'failed') return (Colors.red.shade600, 'Failed');
    if (s == 'refunded') return (Colors.blueGrey.shade600, 'Refunded');
    return (
      Colors.grey.shade700,
      s
          .split('_')
          .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
          .join(' ')
    );
  }

  String? _fmtDate(DateTime? dt) =>
      dt == null ? null : DateFormat('dd MMM yyyy · HH:mm').format(dt);

  Widget _pill(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _kvCard(BuildContext context, String k, String v) {
    final labelStyle = TextStyle(
      fontSize: SizeConfig.textMultiplier * 1.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = TextStyle(
      fontSize: SizeConfig.textMultiplier * 2.0,
      fontWeight: FontWeight.w800,
    );
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k,
              style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(v,
              style: valueStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _timelineRow(
          BuildContext context, IconData icon, String label, String value) =>
      Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

/* ---------- States ---------- */

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            const Text('Order not found',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _Error extends StatelessWidget {
  final String message;
  const _Error({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            const Text('Couldn’t load order',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            )
          ]),
        ),
      );
}
