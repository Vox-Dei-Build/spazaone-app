// lib/pages/sales/widgets/online_sales_list.dart
import 'dart:convert';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/config/function_endpoints.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

// Reuse house components
import 'package:pasella/pages/ecommerce/orders_management/widgets/orders_summary_bar.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_avatar.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/status_pill.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';
import 'package:shimmer/shimmer.dart';
import 'online_sale_detail_page.dart';

class LedgerSale {
  final String id;
  final String reference;
  final String status; // paid | collected | pending | failed | refunded | ...
  final String paymentMethod; // "Online"
  final String paymentStatus; // "paid" | ...
  final int itemsCount;
  final DateTime? createdAt; // sale date
  final DateTime? ledgerCreatedAt; // ledger date
  final double orderTotal; // from sale
  final double amountPaid; // from ledger
  final double feeExVat;
  final double feeInclVat;
  final double netAmount; // ledger
  final String currency;
  final String method; // card|eft|qr|...
  final String channel; // same as method as a fallback

  LedgerSale.fromMap(Map<String, dynamic> m)
      : id = (m['id'] ?? '') as String,
        reference = (m['reference'] ?? '') as String,
        status = (m['status'] ?? 'paid') as String,
        paymentMethod = (m['paymentMethod'] ?? 'Online') as String,
        paymentStatus = (m['paymentStatus'] ?? 'paid') as String,
        itemsCount = (m['itemsCount'] ?? 0).toInt(),
        createdAt = _parseDate(m['createdAt']),
        ledgerCreatedAt = _parseDate(m['ledgerCreatedAt']),
        orderTotal = (m['orderTotal'] as num?)?.toDouble() ?? 0.0,
        amountPaid = (m['amountPaid'] as num?)?.toDouble() ?? 0.0,
        feeExVat = (m['feeExVat'] as num?)?.toDouble() ?? 0.0,
        feeInclVat = (m['feeInclVat'] as num?)?.toDouble() ?? 0.0,
        netAmount = (m['netAmount'] as num?)?.toDouble() ?? 0.0,
        currency = (m['currency'] ?? 'ZAR') as String,
        method = (m['method'] ?? '') as String,
        channel = (m['channel'] ?? '') as String;

  static DateTime? _parseDate(dynamic v) {
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
}

enum OnlineStatusFilter { all, paid, collected, pending, failed, refunded }

Future<List<LedgerSale>> fetchOnlineLedgerSales({
  DateTime? selectedDay,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  final uid = StoreSession.instance.storeId;
  if (uid.isEmpty) throw Exception('Not signed in');

  final url = FunctionEndpoints.https('getOnlineSalesFromLedger');
  String? appCheck;
  try {
    appCheck = await FirebaseAppCheck.instance.getToken();
  } catch (_) {}
  String? idToken;
  try {
    idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (_) {}

  String? startIso;
  String? endIso;
  if (startDate != null && endDate != null) {
    startIso = DateTime(startDate.year, startDate.month, startDate.day)
        .toIso8601String();
    endIso =
        DateTime(endDate.year, endDate.month, endDate.day).toIso8601String();
  } else if (selectedDay != null) {
    startIso = DateTime(selectedDay.year, selectedDay.month, selectedDay.day)
        .toIso8601String();
    endIso = startIso;
  }

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      if (appCheck != null) 'X-Firebase-AppCheck': appCheck,
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    },
    body: jsonEncode({
      'merchantId': uid,
      'limit': 200,
      if (startIso != null) 'startDate': startIso,
      if (endIso != null) 'endDate': endIso,
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Could not load online orders');
  }
  final decoded = jsonDecode(response.body);
  final list = decoded is Map && decoded['sales'] is List
      ? decoded['sales'] as List
      : const <dynamic>[];
  return list
      .whereType<Map>()
      .map((item) => LedgerSale.fromMap(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

class OnlineSalesList extends StatefulWidget {
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  const OnlineSalesList(
      {super.key, this.selectedDay, this.startDate, this.endDate});

  @override
  State<OnlineSalesList> createState() => _OnlineSalesListState();
}

class _OnlineSalesListState extends State<OnlineSalesList> {
  late Future<List<LedgerSale>> _future;
  final _searchCtrl = TextEditingController();
  OnlineStatusFilter _status = OnlineStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant OnlineSalesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameFilters(oldWidget, widget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _future = _fetch());
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _sameFilters(OnlineSalesList a, OnlineSalesList b) {
    return _isSameDay(a.selectedDay, b.selectedDay) &&
        _isSameMoment(a.startDate, b.startDate) &&
        _isSameMoment(a.endDate, b.endDate);
  }

  bool _isSameDay(DateTime? x, DateTime? y) {
    if (x == null && y == null) return true;
    if (x == null || y == null) return false;
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  bool _isSameMoment(DateTime? x, DateTime? y) {
    if (x == null && y == null) return true;
    if (x == null || y == null) return false;
    return x.isAtSameMomentAs(y);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Future<List<LedgerSale>> _fetch() async {
    final items = await fetchOnlineLedgerSales(
      selectedDay: widget.selectedDay,
      startDate: widget.startDate,
      endDate: widget.endDate,
    );
    return _filterByDate(items);
  }

  List<LedgerSale> _filterByDate(List<LedgerSale> items) {
    if (widget.startDate != null && widget.endDate != null) {
      final start = DateTime(widget.startDate!.year, widget.startDate!.month,
          widget.startDate!.day);
      final end = DateTime(
              widget.endDate!.year, widget.endDate!.month, widget.endDate!.day)
          .add(const Duration(days: 1));
      return items.where((o) {
        final ts = o.createdAt ?? o.ledgerCreatedAt;
        return ts != null && !ts.isBefore(start) && ts.isBefore(end);
      }).toList();
    } else if (widget.selectedDay != null) {
      final start = DateTime(widget.selectedDay!.year,
          widget.selectedDay!.month, widget.selectedDay!.day);
      final end = start.add(const Duration(days: 1));
      return items.where((o) {
        final ts = o.createdAt ?? o.ledgerCreatedAt;
        return ts != null && !ts.isBefore(start) && ts.isBefore(end);
      }).toList();
    }
    return items;
  }

  List<LedgerSale> _applyClientFilters(List<LedgerSale> items) {
    final q = _searchCtrl.text.trim().toLowerCase();
    Iterable<LedgerSale> out = items;

    if (_status != OnlineStatusFilter.all) {
      out = out.where((o) => o.status.toLowerCase() == _status.name);
    }
    if (q.isNotEmpty) {
      out = out.where((o) =>
          o.id.toLowerCase().contains(q) ||
          o.reference.toLowerCase().contains(q) ||
          o.method.toLowerCase().contains(q) ||
          o.channel.toLowerCase().contains(q));
    }
    return out.toList();
  }

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(locale: 'en_ZA', symbol: 'R', decimalDigits: 2);

    // spacing tokens
    final hEdge = SizeConfig.imageSizeMultiplier * 2.2; // ~8–9
    final vEdge = SizeConfig.heightMultiplier * 1.0; // ~8
    final rowGap = SizeConfig.heightMultiplier * 0.7; // ~5
    final chipGap = SizeConfig.imageSizeMultiplier * 1.6; // ~6–7

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<LedgerSale>>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return _LoadingList(hPad: hEdge, vPad: vEdge, itemGap: rowGap);
          }
          if (s.hasError) {
            return _ErrorState(
              message: 'Failed to load online sales:\n${s.error}',
              onRetry: _refresh,
              hPad: hEdge,
            );
          }

          final all = s.data ?? const <LedgerSale>[];
          final items = _applyClientFilters(all);

          // Summary bar inputs
          final count = all.length;
          final gross = all.fold<double>(0, (sum, o) => sum + o.orderTotal);
          final rangeText = _rangeLabel();

          return CustomScrollView(
            slivers: [
              //STATUS (dense column)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hEdge, 0, hEdge, vEdge),
                  child: Column(
                    children: [
                      _OnlineStatusChips(
                        selected: _status,
                        onSelected: (v) => setState(() => _status = v),
                        height: SizeConfig.heightMultiplier * 4.0, // slimmer
                        spacing: chipGap,
                      ),
                    ],
                  ),
                ),
              ),

              // SUMMARY — denser
              SliverToBoxAdapter(
                child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(hEdge, vEdge, hEdge, vEdge / 2),
                    child: Column(children: [
                      OrdersSummaryBar(
                        count: count,
                        totalText: money.format(gross),
                        rangeText: rangeText,
                      ),
                      const Divider(color: kHighLightColor, height: 5),
                    ])),
              ),

              if (items.isEmpty)
                const SliverFillRemaining(
                    hasScrollBody: false, child: _EmptyState())
              else
                SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: hEdge,
                    endIndent: hEdge,
                  ),
                  itemBuilder: (context, i) {
                    final o = items[i];
                    final ts = o.createdAt ?? o.ledgerCreatedAt;
                    final dateStr = ts != null
                        ? DateFormat('dd MMM yyyy · HH:mm').format(ts)
                        : '—';
                    final methodLabel =
                        (o.method.isNotEmpty ? o.method : o.channel)
                            .toUpperCase();
                    final (pillColor, statusText) =
                        _statusColorAndText(o.status);

                    return Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: hEdge, vertical: vEdge),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                            SizeConfig.imageSizeMultiplier * 2.8),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  OnlineSaleDetailPage(orderId: o.id)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar
                            OrderAvatar(color: pillColor),
                            SizedBox(
                                width: SizeConfig.imageSizeMultiplier * 2.0),
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: ID + StatusPill
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '#${o.id}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize:
                                                SizeConfig.textMultiplier *
                                                    1.8, // ~13–14
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      StatusPill(
                                          text: statusText, color: pillColor),
                                    ],
                                  ),
                                  SizedBox(height: rowGap),

                                  // Badges
                                  Wrap(
                                    spacing: chipGap,
                                    runSpacing: chipGap / 2,
                                    children: [
                                      _pill(context, methodLabel),
                                      _pill(context,
                                          o.paymentStatus.toUpperCase()),
                                      if (o.itemsCount > 0)
                                        _pill(context, '${o.itemsCount} items'),
                                    ],
                                  ),
                                  SizedBox(height: rowGap),

                                  // Amount rows (denser)
                                  _amountRow(
                                    context,
                                    'Order',
                                    money.format(o.orderTotal),
                                    'Paid',
                                    money.format(o.amountPaid),
                                  ),
                                  SizedBox(height: rowGap / 2),
                                  _amountRow(
                                    context,
                                    'Fees (incl VAT)',
                                    money.format(o.feeInclVat),
                                    'Net',
                                    money.format(o.netAmount),
                                  ),
                                  SizedBox(height: rowGap),

                                  // Date
                                  Row(
                                    children: [
                                      const Icon(Icons.schedule, size: 14),
                                      SizedBox(
                                          width:
                                              SizeConfig.imageSizeMultiplier *
                                                  1.6),
                                      Expanded(
                                        child: Text(
                                          dateStr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize:
                                                SizeConfig.textMultiplier * 1.4,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // tiny bottom spacer
              SliverToBoxAdapter(child: SizedBox(height: vEdge)),
            ],
          );
        },
      ),
    );
  }

  String _rangeLabel() {
    String fmt(DateTime d) => DateFormat('dd MMM yyyy').format(d);
    if (widget.startDate != null && widget.endDate != null) {
      return '${fmt(widget.startDate!)} — ${fmt(widget.endDate!)}';
    } else if (widget.selectedDay != null) {
      return fmt(widget.selectedDay!);
    }
    return 'All time';
  }

  (Color, String) _statusColorAndText(String raw) {
    final s = raw.toLowerCase();
    if (s == 'paid') return (Colors.green.shade600, 'Paid');
    if (s == 'collected') return (Colors.teal.shade600, 'Collected');
    if (s == 'pending') return (Colors.orange.shade700, 'Pending');
    if (s == 'failed') return (Colors.red.shade600, 'Failed');
    if (s == 'refunded') return (Colors.blueGrey.shade600, 'Refunded');
    return (Colors.grey.shade700, _titleCase(s.replaceAll('_', ' ')));
  }

  String _titleCase(String t) => t
      .split(' ')
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');

  Widget _pill(BuildContext context, String text) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 2.0,
          vertical: SizeConfig.heightMultiplier * 0.6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant, width: 0.7),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.2, // ~9–10
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _amountRow(
    BuildContext context,
    String k1,
    String v1,
    String k2,
    String v2,
  ) {
    final label = TextStyle(
      fontSize: SizeConfig.textMultiplier * 1.2, // ~9–10
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final value = TextStyle(
      fontSize: SizeConfig.textMultiplier * 1.7, // ~12–13
      fontWeight: FontWeight.w800,
    );
    return Row(
      children: [
        Expanded(child: _kv(k1, v1, label, value)),
        SizedBox(width: SizeConfig.imageSizeMultiplier * 2.0),
        Expanded(child: _kv(k2, v2, label, value)),
      ],
    );
  }

  Widget _kv(String k, String v, TextStyle l, TextStyle val) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: l, maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: SizeConfig.heightMultiplier * 0.2),
          Text(v, style: val, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
}

/* ---------- UI bits ---------- */

class _OnlineStatusChips extends StatelessWidget {
  const _OnlineStatusChips({
    required this.selected,
    required this.onSelected,
    this.height,
    this.spacing,
  });

  final OnlineStatusFilter selected;
  final ValueChanged<OnlineStatusFilter> onSelected;
  final double? height;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final selColor = Theme.of(context).colorScheme.primary;
    final unSelBg =
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6);
    const statuses = OnlineStatusFilter.values;

    final h = height ?? 40.0;
    final gap = spacing ?? 8.0;

    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: statuses.length,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (context, i) {
          final s = statuses[i];
          final isSel = s == selected;
          final label = switch (s) {
            OnlineStatusFilter.all => 'All',
            OnlineStatusFilter.paid => 'Paid',
            OnlineStatusFilter.collected => 'Collected',
            OnlineStatusFilter.pending => 'Pending',
            OnlineStatusFilter.failed => 'Failed',
            OnlineStatusFilter.refunded => 'Refunded',
          };
          return RawChip(
            showCheckmark: false, // keep the big default check off
            avatar: null, // <— remove avatar to avoid the fixed gap

            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSel)
                  Padding(
                    padding: EdgeInsets.only(
                      right: SizeConfig.imageSizeMultiplier *
                          0.8, // fine-grained gap (≈3–4px)
                    ),
                    child: Icon(
                      Icons.check,
                      size: SizeConfig.textMultiplier * 1.7,
                      color: Colors.white,
                    ),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    color: isSel ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),

            // tighten overall padding
            labelPadding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier *
                  1.5, // slightly smaller than before
            ),
            padding: const EdgeInsets.all(2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            selected: isSel,
            onSelected: (_) => onSelected(s),
            selectedColor: selColor,
            backgroundColor: unSelBg,
            shape: StadiumBorder(
              side: BorderSide(
                color: isSel ? selColor : Colors.white,
                width: 0.5,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({this.hPad = 12, this.vPad = 8, this.itemGap = 8});
  final double hPad;
  final double vPad;
  final double itemGap;

  @override
  Widget build(BuildContext context) {
    // Helper builders
    Widget bar(double h, {double? w, double r = 8}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(r),
          ),
        );

    Widget pill({double w = 60, double h = 18}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.grey,
            borderRadius: BorderRadius.circular(999),
          ),
        );

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
      itemCount: 6,
      separatorBuilder: (_, __) => SizedBox(height: itemGap),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.black12,
        highlightColor: Colors.black26,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 2.2, // match list
            vertical: SizeConfig.heightMultiplier * 1.0,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(
              SizeConfig.imageSizeMultiplier * 2.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar placeholder
              Container(
                height: SizeConfig.imageSizeMultiplier * 7.2,
                width: SizeConfig.imageSizeMultiplier * 7.2,
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2.0),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + status pill row
                    Row(
                      children: [
                        Expanded(
                          child: bar(SizeConfig.textMultiplier * 1.8,
                              r: 6), // title line
                        ),
                        const SizedBox(width: 8),
                        pill(w: 64, h: 18), // status pill
                      ],
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.7),

                    // Badges
                    Wrap(
                      spacing: SizeConfig.imageSizeMultiplier * 1.6,
                      runSpacing: SizeConfig.imageSizeMultiplier * 0.8,
                      children: [
                        pill(w: 48, h: 16),
                        pill(w: 72, h: 16),
                        pill(w: 56, h: 16),
                      ],
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.7),

                    // Amount rows (two columns)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(SizeConfig.textMultiplier * 1.2, w: 60, r: 6),
                              SizedBox(
                                  height: SizeConfig.heightMultiplier * 0.2),
                              bar(SizeConfig.textMultiplier * 1.7, w: 90, r: 6),
                            ],
                          ),
                        ),
                        SizedBox(width: SizeConfig.imageSizeMultiplier * 2.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(SizeConfig.textMultiplier * 1.2, w: 60, r: 6),
                              SizedBox(
                                  height: SizeConfig.heightMultiplier * 0.2),
                              bar(SizeConfig.textMultiplier * 1.7, w: 90, r: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.7),

                    // Date row
                    Row(
                      children: [
                        // tiny icon circle
                        Container(
                          height: 14,
                          width: 14,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        SizedBox(width: SizeConfig.imageSizeMultiplier * 1.6),
                        Expanded(
                          child: bar(SizeConfig.textMultiplier * 1.4, r: 6),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return ScrollableCenteredContent(
      padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3.2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long,
              size: SizeConfig.imageSizeMultiplier * 8.0,
              color: Theme.of(context).colorScheme.outline),
          SizedBox(height: SizeConfig.heightMultiplier * 1.0),
          Text(
            'No online sales for this filter',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: SizeConfig.textMultiplier * 1.6),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 0.4),
          Text(
            'Try adjusting the date, status, or search.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.3,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, required this.onRetry, this.hPad = 12});
  final String message;
  final VoidCallback onRetry;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    return ScrollableCenteredContent(
      padding: EdgeInsets.all(hPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off,
              size: SizeConfig.imageSizeMultiplier * 8.0,
              color: Theme.of(context).colorScheme.error),
          SizedBox(height: SizeConfig.heightMultiplier * 0.8),
          Text(
            'Couldn’t load sales',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: SizeConfig.textMultiplier * 1.7),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 0.6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.3),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 0.8),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
