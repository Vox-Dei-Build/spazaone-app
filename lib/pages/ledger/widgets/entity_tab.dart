import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/customer/customer_model.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/transactions/transaction_model.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/services/whatsapp_capability_cache.dart';
import 'package:pasella/shared/widgets/onboarding/activation_coachmark.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

@visibleForTesting
bool customerSnapshotIsUnverified({
  required bool isFromCache,
  required bool isEmpty,
}) =>
    isFromCache && isEmpty;

class _CustomerCacheUnverified implements Exception {
  const _CustomerCacheUnverified();
}

class EntityTab extends StatefulWidget {
  final String category;
  final String emptyAsset;
  final String emptyText;
  final ValueNotifier<String?> searchTextNotifier;
  final ValueNotifier<bool> hasCustomersNotifier;

  /// Optional source override used by focused widget tests. Production keeps
  /// the Firestore-backed stream below.
  final Stream<List<CustomerWithTransactions>> Function()? entitiesStream;

  /// PAS-UX: optional external scroll controller. When provided, the
  /// inner `SingleChildScrollView` attaches to it so a parent (e.g.
  /// `CustomerTab`) can listen for scroll direction and drive the
  /// sticky-on-scroll behavior of the search bar above. Optional so
  /// other categories that don't need this behavior keep their
  /// implicit controller.
  final ScrollController? scrollController;

  /// PAS-UX-09: optional inline CTA on the empty state. When supplied
  /// the empty surface paints a primary action button beneath the
  /// caption (mirrors the PAS-UX-04 stock empty-state recovery
  /// pattern). Optional so non-onboarding categories can keep the
  /// bare image + caption.
  final String? emptyCtaLabel;
  final VoidCallback? onEmptyCtaTap;

  /// PAS-AUTH-03: optional walkthrough video key. When set and the
  /// matching Remote Config entry returns a non-empty URL, a "Watch a
  /// 2-min walkthrough" link is rendered below the primary CTA — same
  /// pattern Stock already uses. Kept on EntityTab (vs. only on
  /// CustomerTab) so future tabs (Supplier, etc.) can opt in.
  final String? tutorialKey;
  final String tutorialTitle;

  const EntityTab({
    required this.searchTextNotifier,
    required this.category,
    required this.emptyAsset,
    required this.emptyText,
    required this.hasCustomersNotifier,
    this.entitiesStream,
    this.scrollController,
    this.emptyCtaLabel,
    this.onEmptyCtaTap,
    this.tutorialKey,
    this.tutorialTitle = 'How to use Spaza One',
    Key? key,
  }) : super(key: key);

  @override
  State<EntityTab> createState() => _EntityTabState();
}

class _EntityTabState extends State<EntityTab> {
  List<CustomerWithTransactions> allEntities = [];
  int _streamGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.searchTextNotifier.value = null;
    widget.searchTextNotifier.addListener(_handleSearch);
  }

  @override
  void didUpdateWidget(EntityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTextNotifier != widget.searchTextNotifier) {
      oldWidget.searchTextNotifier.removeListener(_handleSearch);
      widget.searchTextNotifier.addListener(_handleSearch);
      _handleSearch();
    }
  }

  void _handleSearch() {
    if (!mounted) return;
    setState(() {});
  }

  Stream<List<CustomerWithTransactions>> streamEntitiesWithTransactions() {
    final String currentUserId = StoreSession.instance.storeId;
    if (currentUserId.isEmpty) return Stream.value([]);

    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: widget.category);

    final customersStream = query
        .orderBy("lastTransaction.date", descending: true)
        .snapshots(includeMetadataChanges: true);

    final unreadMessagesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data()?['unreadMessages'] == null) {
        return <Map<String, dynamic>>[];
      }
      return (snapshot.data()?['unreadMessages'] as List<dynamic>)
          .map((msg) => msg as Map<String, dynamic>)
          .toList();
    });

    return Rx.combineLatest2<QuerySnapshot, List<Map<String, dynamic>>,
        List<CustomerWithTransactions>>(
      customersStream,
      unreadMessagesStream,
      (customerSnapshot, unreadMessages) {
        if (customerSnapshotIsUnverified(
          isFromCache: customerSnapshot.metadata.isFromCache,
          isEmpty: customerSnapshot.docs.isEmpty,
        )) {
          throw const _CustomerCacheUnverified();
        }
        return customerSnapshot.docs.map((customerDoc) {
          final customerData = customerDoc.data() as Map<String, dynamic>;
          final double balance =
              (customerData['balance'] as num?)?.toDouble() ?? 0.0;

          // 🔵 Chat unread per customer (existing)
          // V1 truth-surface: only count inbound customer messages toward
          // the unread badge — outbound bot mirrors share the same array
          // but should not ring the bell. Entries flagged `isRead: true`
          // by `markMessagesAsRead` must also be excluded so the badge
          // actually clears after the merchant opens the chat.
          final legacyChatUnread = unreadMessages
              .where(
                (msg) =>
                    msg['customerNumber'] == customerData['number'] &&
                    (msg['direction'] == null ||
                        msg['direction'].toString().toLowerCase() ==
                            'inbound') &&
                    msg['isRead'] != true,
              )
              .length;
          final nestedUnread = customerData['unreadCounts'];
          final chatUnread = nestedUnread is Map &&
                  nestedUnread['messages'] is num
              ? (nestedUnread['messages'] as num).toInt()
              : legacyChatUnread;

          // 🟠 Orders unread per customer (NEW)
          final int ordersUnread = nestedUnread is Map &&
                  nestedUnread['orders'] is num
              ? (nestedUnread['orders'] as num).toInt()
              : (customerData['ordersUnreadCount'] as int?) ?? 0;

          // ✅ Single badge shows combined unread (messages + orders)
          final int combinedUnread = chatUnread + ordersUnread;

          return CustomerWithTransactions(
            customer: Customer.fromMap({
              'id': customerDoc.id,
              'name': formatStringToCamelCase(customerData['name']),
              'number': customerData['number'],
              'category': customerData['category'],
              'lastTransaction': customerData['lastTransaction'],
              'balance': balance,
              'isNPA': balance < 0,
              'profileImageUrl': customerData['profileImageUrl'],
            }),
            transactions: [],
            unreadCount: combinedUnread,
          );
        }).toList();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final currentUserId =
        widget.entitiesStream == null ? StoreSession.instance.storeId : '';
    final dataModel = context.watch<AppModel>();
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 2,
        ),
        child: StreamBuilder<List<CustomerWithTransactions>>(
          key: ValueKey(
            dataModel.selectedSortByFilter +
                dataModel.reminderDateFilter.toString() +
                _streamGeneration.toString(),
          ),
          stream:
              widget.entitiesStream?.call() ?? streamEntitiesWithTransactions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // A failed Firestore read is not an empty customer list. Surface
            // the connection problem before examining data so a transient
            // error can never masquerade as first-run onboarding.
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: SizeConfig.imageSizeMultiplier * 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 32),
                      SizedBox(height: SizeConfig.heightMultiplier),
                      const Text(
                        'Could not load customers.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const ValueKey('customer-stream-retry'),
                        onPressed: () {
                          setState(() => _streamGeneration++);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.hasCustomersNotifier.value = false;
              });
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        widget.emptyAsset,
                        width: SizeConfig.imageSizeMultiplier * 60,
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: SizeConfig.imageSizeMultiplier * 6,
                        ),
                        child: Text(
                          widget.emptyText,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // PAS-UX-09: inline recovery CTA. Previously the
                      // empty Customers tab dead-ended on image + text
                      // and required the merchant to find the floating
                      // "+" FAB (easy to miss on small screens). Now
                      // the empty state itself is the onboarding
                      // moment.
                      if (widget.emptyCtaLabel != null &&
                          widget.onEmptyCtaTap != null) ...[
                        SizedBox(height: SizeConfig.heightMultiplier * 3),
                        ActivationCoachmark(
                          userId: currentUserId,
                          coachmarkKey: 'add_first_customer',
                          title: 'Start with one customer',
                          message:
                              'Save one real customer. Spaza One opens their Pay Later screen next.',
                          icon: Icons.person_add_alt_1_outlined,
                          enabled: widget.category == 'Customer',
                          child: ElevatedButton.icon(
                            onPressed: widget.onEmptyCtaTap,
                            icon: const Icon(Icons.person_add),
                            label: Text(widget.emptyCtaLabel!),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: SizeConfig.imageSizeMultiplier * 6,
                                vertical: SizeConfig.heightMultiplier * 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                      // PAS-AUTH-03: secondary walkthrough link. Only
                      // renders when Remote Config has a URL for the
                      // tutorial key — silently hidden otherwise so we
                      // never show a button that opens an empty
                      // WebView.
                      if (widget.tutorialKey != null) ...[
                        Builder(
                          builder: (context) {
                            final url = TutorialConfig.getTutorialUrl(
                              widget.tutorialKey!,
                            );
                            if (url.isEmpty) return const SizedBox.shrink();
                            return Column(
                              children: [
                                SizedBox(
                                  height: SizeConfig.heightMultiplier * 1,
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LoomVideoPage(
                                          loomUrl: url,
                                          title: widget.tutorialTitle,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.play_circle_outline),
                                  label: const Text(
                                    'Watch a 2-min walkthrough',
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            allEntities = snapshot.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.hasCustomersNotifier.value = allEntities.isNotEmpty;
            });

            // Prime channel capability in bulk. The process-wide cache skips
            // known and in-flight numbers, and queries Firestore in chunks,
            // so customer rows never trigger one read per tile.
            final customerNumbers = allEntities
                .map((entity) => entity.customer.number)
                .whereType<String>()
                .where((number) => number.isNotEmpty)
                .toSet();
            if (customerNumbers.isNotEmpty) {
              // ignore: unawaited_futures
              WhatsAppCapabilityCache.instance.primeFor(customerNumbers);
            }

            List<CustomerWithTransactions> filteredEntities =
                dataModel.applyFilters(allEntities);

            String? searchTerm = widget.searchTextNotifier.value?.toLowerCase();
            if (searchTerm != null && searchTerm.isNotEmpty) {
              filteredEntities = filteredEntities.where((entity) {
                return entity.customer.name.toLowerCase().contains(
                      searchTerm,
                    );
              }).toList();
            }

            if (filteredEntities.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      widget.emptyAsset,
                      width: SizeConfig.imageSizeMultiplier * 70,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Text(
                      'No results found.',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: SizeConfig.textMultiplier * 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return AnimatedBuilder(
              animation: WhatsAppCapabilityCache.instance,
              builder: (context, _) => SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  children: [
                    ...filteredEntities.map((entityWithTransactions) {
                      LedgerTransaction? lastTransaction;
                      double balance = entityWithTransactions.customer.balance;

                      if (entityWithTransactions.customer.lastTransaction !=
                              null &&
                          entityWithTransactions
                              .customer.lastTransaction!.isNotEmpty) {
                        lastTransaction = LedgerTransaction.fromMap(
                          entityWithTransactions.customer.lastTransaction!,
                        );
                      }

                      return TransactionTile(
                        color: kTertiaryColor.toARGB32(),
                        name: entityWithTransactions.customer.name,
                        profileImageUrl:
                            entityWithTransactions.customer.profileImageUrl,
                        balance: balance,
                        amount: lastTransaction != null
                            ? lastTransaction.amount.toDouble()
                            : 0,
                        remarks:
                            lastTransaction?.remarks ?? 'No transactions yet',
                        status: lastTransaction?.status ?? 'DUE',
                        type: lastTransaction?.type ?? 'Credit',
                        date: lastTransaction?.date != null
                            ? DateFormat(
                                'y MMM d, h:mm a',
                              ).format(lastTransaction!.date)
                            : '',
                        selectedCustomerId: entityWithTransactions.customer.id,
                        isNPA: entityWithTransactions.customer.isNPA,
                        number: entityWithTransactions.customer.number,
                        unreadCount: entityWithTransactions.unreadCount,
                        showChannelCapability: widget.category == 'Customer',
                        hasWhatsApp:
                            WhatsAppCapabilityCache.instance.capabilityFor(
                          entityWithTransactions.customer.number,
                        ),
                      );
                    }),
                    const SizedBox(height: 112),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.searchTextNotifier.removeListener(_handleSearch);
    super.dispose();
  }
}
