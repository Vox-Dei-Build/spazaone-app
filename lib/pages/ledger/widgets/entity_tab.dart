import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/customer/customer_model.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/transactions/transaction_model.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/services/whatsapp_capability_cache.dart';
import 'package:pasella/shared/widgets/onboarding/activation_coachmark.dart';
import 'package:pasella/shared/widgets/onboarding/customer_growth_nudge.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

class EntityTab extends StatefulWidget {
  final String category;
  final String emptyAsset;
  final String emptyText;
  final ValueNotifier<String?> searchTextNotifier;
  final ValueNotifier<bool> hasCustomersNotifier;

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

  /// Optional non-empty list header. CustomerTab uses this for the
  /// customer setup checklist so the card scrolls with the customer
  /// list instead of consuming fixed vertical space above it.
  final Widget? listHeader;

  /// PAS-UX-rel: Whether to render the [CustomerGrowthNudge] beneath
  /// [listHeader] when the category is Customer. Only meaningful on
  /// the Customer tab; other categories ignore it.
  ///
  /// CustomerTab hides the growth nudge while the merchant setup card
  /// still has incomplete steps — two overlapping progress surfaces
  /// on the same tab was the top piece of noise merchants called out
  /// in the design review. Activation first, growth after.
  final ValueListenable<bool>? showGrowthNudge;

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
    this.scrollController,
    this.emptyCtaLabel,
    this.onEmptyCtaTap,
    this.listHeader,
    this.showGrowthNudge,
    this.tutorialKey,
    this.tutorialTitle = 'How to use Pasella',
    Key? key,
  }) : super(key: key);

  @override
  _EntityTabState createState() => _EntityTabState();
}

class _EntityTabState extends State<EntityTab> {
  List<CustomerWithTransactions> allEntities = [];

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

  /* Stream<List<CustomerWithTransactions>> streamEntitiesWithTransactions() {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (currentUserId.isEmpty) {
      return Stream.value([]);
    }

    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: widget.category);

    final customersStream =
        query.orderBy("lastTransaction.date", descending: true).snapshots();

    final unreadMessagesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data()?['unreadMessages'] == null) {
        return <Map<String,
            dynamic>>[]; // ✅ Always return a properly typed empty list
      }
      return (snapshot.data()?['unreadMessages'] as List<dynamic>)
          .map((msg) =>
              msg as Map<String, dynamic>) // ✅ Explicitly cast each item
          .toList();
    });

    // ✅ Combine both streams so that unread messages update in real-time
    return Rx.combineLatest2<QuerySnapshot, List<Map<String, dynamic>>,
        List<CustomerWithTransactions>>(
      customersStream,
      unreadMessagesStream,
      (customerSnapshot, unreadMessages) =>
          customerSnapshot.docs.map((customerDoc) {
        final customerData = customerDoc.data() as Map<String, dynamic>;
        double balance = customerData['balance']?.toDouble() ?? 0.0;

        // ✅ Filter unread messages for this specific customer
        int unreadCount = unreadMessages
            .where((msg) => msg['customerNumber'] == customerData['number'])
            .length;

        return CustomerWithTransactions(
          customer: Customer.fromMap({
            'id': customerDoc.id,
            'name': formatStringToCamelCase(customerData['name']),
            'number': customerData['number'],
            'category': customerData['category'],
            'lastTransaction': customerData['lastTransaction'],
            'balance': balance,
            'isNPA': customerData['isNPA'],
            'profileImageUrl': customerData['profileImageUrl'],
          }),
          transactions: [],
          unreadCount: unreadCount, // ✅ UI updates when unread messages change
        );
      }).toList(), // ✅ Ensure this function returns a List<CustomerWithTransactions>
    );
  }
 */

  Stream<List<CustomerWithTransactions>> streamEntitiesWithTransactions() {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return Stream.value([]);

    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: widget.category);

    final customersStream =
        query.orderBy("lastTransaction.date", descending: true).snapshots();

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

    return Rx.combineLatest2<
      QuerySnapshot,
      List<Map<String, dynamic>>,
      List<CustomerWithTransactions>
    >(
      customersStream,
      unreadMessagesStream,
      (customerSnapshot, unreadMessages) =>
          customerSnapshot.docs.map((customerDoc) {
            final customerData = customerDoc.data() as Map<String, dynamic>;
            final double balance =
                (customerData['balance'] as num?)?.toDouble() ?? 0.0;

            // 🔵 Chat unread per customer (existing)
            // V1 truth-surface: only count inbound customer messages toward
            // the unread badge — outbound bot mirrors share the same array
            // but should not ring the bell. Entries flagged `isRead: true`
            // by `markMessagesAsRead` must also be excluded so the badge
            // actually clears after the merchant opens the chat.
            final chatUnread =
                unreadMessages
                    .where(
                      (msg) =>
                          msg['customerNumber'] == customerData['number'] &&
                          (msg['direction'] == null ||
                              msg['direction'].toString().toLowerCase() ==
                                  'inbound') &&
                          msg['isRead'] != true,
                    )
                    .length;

            // 🟠 Orders unread per customer (NEW)
            final int ordersUnread =
                (customerData['ordersUnreadCount'] as int?) ?? 0;

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
              unreadCount: combinedUnread, // 👈 now includes orders
            );
          }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final dataModel = context.watch<AppModel>();
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 2,
        ),
        child: StreamBuilder<List<CustomerWithTransactions>>(
          key: ValueKey(
            dataModel.selectedSortByFilter +
                dataModel.reminderDateFilter.toString(),
          ),
          stream: streamEntitiesWithTransactions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
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
                              'Save one real customer. Pasella opens their Pay Later screen next.',
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
                                        builder:
                                            (_) => LoomVideoPage(
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

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load customers. Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
              );
            }

            allEntities = snapshot.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.hasCustomersNotifier.value = allEntities.isNotEmpty;
            });

            // PAS-WA-V1: prime the WhatsApp-capability cache for any
            // numbers we haven't looked up yet. Bulk-loads via chunked
            // `whereIn`, so the per-row Firestore cost stays at zero
            // even on a 200-customer ledger. Already-known numbers are
            // skipped inside the cache, making this safe to call on
            // every stream tick.
            final numbers =
                allEntities
                    .map((e) => e.customer.number)
                    .whereType<String>()
                    .where((n) => n.isNotEmpty)
                    .toSet();
            if (numbers.isNotEmpty) {
              // ignore: unawaited_futures
              WhatsAppCapabilityCache.instance.primeFor(numbers);
            }

            List<CustomerWithTransactions> filteredEntities = dataModel
                .applyFilters(allEntities);

            String? searchTerm = widget.searchTextNotifier.value?.toLowerCase();
            final hasSearchTerm =
                searchTerm != null && searchTerm.trim().isNotEmpty;
            if (searchTerm != null && searchTerm.isNotEmpty) {
              filteredEntities =
                  filteredEntities.where((entity) {
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

            // PAS-WA-V1: rebuild only the list when capability data
            // arrives — the rest of the surface (filters, empty state,
            // etc.) is already settled by this point.
            return AnimatedBuilder(
              animation: WhatsAppCapabilityCache.instance,
              builder: (context, _) {
                return SingleChildScrollView(
                  controller: widget.scrollController,
                  child: Column(
                    children: [
                      if (!hasSearchTerm && widget.listHeader != null)
                        widget.listHeader!,
                      if (widget.category == 'Customer' && !hasSearchTerm)
                        _MaybeGrowthNudge(
                          showGrowthNudge: widget.showGrowthNudge,
                          customerCount: allEntities.length,
                          onAddCustomer: widget.onEmptyCtaTap,
                        ),
                      ...filteredEntities.map((entityWithTransactions) {
                        LedgerTransaction? lastTransaction;
                        double balance =
                            entityWithTransactions.customer.balance;

                        if (entityWithTransactions.customer.lastTransaction !=
                                null &&
                            entityWithTransactions
                                .customer
                                .lastTransaction!
                                .isNotEmpty) {
                          lastTransaction = LedgerTransaction.fromMap(
                            entityWithTransactions.customer.lastTransaction!,
                          );
                        }

                        return TransactionTile(
                          color: kTertiaryColor.value,
                          name: entityWithTransactions.customer.name,
                          profileImageUrl:
                              entityWithTransactions.customer.profileImageUrl,
                          balance: balance,
                          amount:
                              lastTransaction != null
                                  ? lastTransaction.amount.toDouble()
                                  : 0,
                          remarks:
                              lastTransaction?.remarks ?? 'No transactions yet',
                          status: lastTransaction?.status ?? 'DUE',
                          type: lastTransaction?.type ?? 'Credit',
                          date:
                              lastTransaction?.date != null
                                  ? DateFormat(
                                    'y MMM d, h:mm a',
                                  ).format(lastTransaction!.date)
                                  : '',
                          selectedCustomerId:
                              entityWithTransactions.customer.id,
                          isNPA: entityWithTransactions.customer.isNPA,
                          number: entityWithTransactions.customer.number,
                          unreadCount: entityWithTransactions.unreadCount,
                          hasWhatsApp: WhatsAppCapabilityCache.instance
                              .capabilityFor(
                                entityWithTransactions.customer.number,
                              ),
                        );
                      }),
                      const SizedBox(height: 112),
                    ],
                  ),
                );
              },
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

/// Renders the customer growth nudge only when the parent surface has
/// opted-in via [showGrowthNudge]. If [showGrowthNudge] is null the
/// nudge is always visible — preserves behaviour for callers that
/// don't participate in the setup-first / growth-second gating.
class _MaybeGrowthNudge extends StatelessWidget {
  const _MaybeGrowthNudge({
    required this.showGrowthNudge,
    required this.customerCount,
    required this.onAddCustomer,
  });

  final ValueListenable<bool>? showGrowthNudge;
  final int customerCount;
  final VoidCallback? onAddCustomer;

  @override
  Widget build(BuildContext context) {
    final gate = showGrowthNudge;
    if (gate == null) {
      return CustomerGrowthNudge(
        customerCount: customerCount,
        onAddCustomer: onAddCustomer,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: gate,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return CustomerGrowthNudge(
          customerCount: customerCount,
          onAddCustomer: onAddCustomer,
        );
      },
    );
  }
}
