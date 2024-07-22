import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/customer/customer_model.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/transactions/transaction_model.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';
import 'package:provider/provider.dart';

class EntityTab extends StatefulWidget {
  final String category;
  final String emptyAsset;
  final String emptyText;
  final ValueNotifier<String?> searchTextNotifier;
  final ValueNotifier<bool> hasCustomersNotifier;

  EntityTab({
    required this.searchTextNotifier,
    required this.category,
    required this.emptyAsset,
    required this.emptyText,
    required this.hasCustomersNotifier,
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
    setState(() {});
  }

  Stream<List<CustomerWithTransactions>> streamEntitiesWithTransactions() {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (currentUserId.isEmpty) {
      return Stream.empty();
    }

    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: widget.category);

    final customersStream =
        query.orderBy("lastTransaction.date", descending: true).snapshots();

    return customersStream.map((snapshot) {
      final entities = snapshot.docs.map((customerDoc) {
        final customerData = customerDoc.data() as Map<String, dynamic>;
        double balance = customerData['balance'].toDouble() ?? 0.0;

        return CustomerWithTransactions(
          customer: Customer.fromMap({
            'id': customerDoc.id,
            'name': formatStringToCamelCase(customerData['name']),
            'number': customerData['number'],
            'category': customerData['category'],
            'lastTransaction': customerData['lastTransaction'],
            'balance': balance,
            'isNPA': customerData['isNPA'],
            'profileImageUrl':
                customerData['profileImageUrl'], // Include profile image URL
          }),
          transactions: [],
        );
      }).toList();

      return entities;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final dataModel = context.watch<AppModel>();
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 2),
        child: StreamBuilder<List<CustomerWithTransactions>>(
          key: ValueKey(dataModel.selectedSortByFilter +
              dataModel.reminderDateFilter.toString()),
          stream: streamEntitiesWithTransactions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(),
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
                      Text(
                        widget.emptyText,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: SizeConfig.textMultiplier * 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            allEntities = snapshot.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.hasCustomersNotifier.value = allEntities.isNotEmpty;
            });

            List<CustomerWithTransactions> filteredEntities =
                dataModel.applyFilters(allEntities);

            String? searchTerm = widget.searchTextNotifier.value?.toLowerCase();
            if (searchTerm != null && searchTerm.isNotEmpty) {
              filteredEntities = filteredEntities.where((entity) {
                return entity.customer.name.toLowerCase().contains(searchTerm);
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

            return SingleChildScrollView(
              child: Column(
                children: filteredEntities.map((entityWithTransactions) {
                  LedgerTransaction? lastTransaction;
                  double balance = entityWithTransactions.customer.balance;

                  if (entityWithTransactions.customer.lastTransaction != null &&
                      entityWithTransactions
                          .customer.lastTransaction!.isNotEmpty) {
                    lastTransaction = LedgerTransaction.fromMap(
                        entityWithTransactions.customer.lastTransaction!);
                  }

                  return TransactionTile(
                    color: kTertiaryColor.value,
                    name: entityWithTransactions.customer.name,
                    profileImageUrl: entityWithTransactions
                        .customer.profileImageUrl, // Pass profile image URL
                    balance: balance,
                    amount: lastTransaction != null
                        ? lastTransaction.amount.toDouble()
                        : 0,
                    remarks: lastTransaction?.remarks ?? 'No transactions yet',
                    status: lastTransaction?.status ?? 'DUE',
                    type: lastTransaction?.type ?? 'Credit',
                    date: lastTransaction?.date != null
                        ? DateFormat('y MMM d, h:mm a')
                            .format(lastTransaction!.date)
                        : '',
                    selectedCustomerId: entityWithTransactions.customer.id,
                    isNPA: entityWithTransactions.customer.isNPA,
                    number: entityWithTransactions.customer.number,
                  );
                }).toList(),
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
