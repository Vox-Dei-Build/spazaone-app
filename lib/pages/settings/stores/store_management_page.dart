import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'package:provider/provider.dart';

class StoreManagementPage extends StatefulWidget {
  const StoreManagementPage({super.key});

  @override
  State<StoreManagementPage> createState() => _StoreManagementPageState();
}

class _StoreManagementPageState extends State<StoreManagementPage> {
  Future<Map<String, dynamic>>? _operators;
  String? _operatorsStoreId;

  void _refreshOperators() {
    final session = StoreSession.instance;
    if (session.activeStore == null) {
      _operatorsStoreId = null;
      _operators = null;
      return;
    }
    _operatorsStoreId = session.storeId;
    _operators = session.loadOperators();
  }

  Future<Map<String, dynamic>> _operatorsFor(StoreSession session) {
    if (_operators == null || _operatorsStoreId != session.storeId) {
      _operatorsStoreId = session.storeId;
      _operators = session.loadOperators();
    }
    return _operators!;
  }

  String _errorMessage(Object error) {
    if (error is FirebaseFunctionsException && error.message != null) {
      return error.message!;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _switchStore(String storeId) async {
    if (storeId == StoreSession.instance.storeId) return;
    await StoreSession.instance.selectStore(storeId);
    await FCMService().handleToken();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  Future<void> _createStore() async {
    final nameController = TextEditingController();
    final operatorController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.displayName ?? '',
    );
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a store'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Store name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: operatorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Your SpazaOne balance is automatically shared across '
                      'every store you own. Sales and withdrawals '
                      'stay separate.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create store'),
          ),
        ],
      ),
    );
    if (submitted != true) return;

    try {
      final store = await StoreSession.instance.createStore(
        name: nameController.text,
        operatorName: operatorController.text,
      );
      await FCMService().handleToken();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.sharedCampaignCredits
                ? '${store.storeName} is ready with your shared SpazaOne balance.'
                : '${store.storeName} is ready.',
          ),
        ),
      );
      setState(_refreshOperators);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  Future<void> _inviteOperator() async {
    final phoneController = TextEditingController();
    var role = StoreRole.operator;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add an operator'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'South African mobile number',
                  hintText: '082 123 4567',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StoreRole>(
                value: role,
                decoration: const InputDecoration(labelText: 'Access level'),
                items: const [
                  DropdownMenuItem(
                    value: StoreRole.operator,
                    child: Text('Operator — use store features'),
                  ),
                  DropdownMenuItem(
                    value: StoreRole.admin,
                    child: Text('Admin — also manage operators'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => role = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add operator'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;

    try {
      final status = await StoreSession.instance.inviteOperator(
        phone: phoneController.text,
        role: role,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'added'
                ? 'Operator added.'
                : 'Invite saved. Access activates when they register.',
          ),
        ),
      );
      setState(_refreshOperators);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  Future<void> _removeOperator(String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove operator?'),
        content: Text(
          '$name will immediately lose access and stop receiving notifications for this store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep access'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StoreSession.instance.removeOperator(uid);
      if (!mounted) return;
      setState(_refreshOperators);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name was removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  Future<void> _cancelInvite(String inviteId) async {
    try {
      await StoreSession.instance.cancelInvite(inviteId);
      if (!mounted) return;
      setState(_refreshOperators);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation cancelled.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const CustomAppBar(title: 'Stores & team'),
      body: Consumer<StoreSession>(
        builder: (context, session, _) {
          Future<void> refresh() async {
            await session.bootstrap();
            if (session.stores.isNotEmpty && mounted) {
              setState(_refreshOperators);
            }
          }

          if (session.stores.isEmpty) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _StoreAccessStateCard(
                    loading: session.loading,
                    connectionIssue: session.lastError != null,
                    onRetry: session.loading ? null : refresh,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ActiveStoreCard(session: session),
                const SizedBox(height: SpazaSpace.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your stores',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _createStore,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add store'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SpazaRadius.surface),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: List.generate(session.stores.length, (index) {
                      final store = session.stores[index];
                      final active = store.storeId == session.storeId;
                      return Column(
                        children: [
                          ListTile(
                            minVerticalPadding: 12,
                            onTap: active
                                ? null
                                : () => _switchStore(store.storeId),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: active
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.10,
                                      )
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                SpazaIcons.shop,
                                color: active
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              store.storeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${_roleLabel(store.role)}${store.sharedCampaignCredits ? ' · Shared SpazaOne balance' : ''}',
                            ),
                            trailing: active
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: theme.colorScheme.primary,
                                  )
                                : const Icon(SpazaIcons.next),
                          ),
                          if (index < session.stores.length - 1)
                            const Divider(height: 1, indent: 70),
                        ],
                      );
                    }),
                  ),
                ),
                const SizedBox(height: SpazaSpace.xl),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Team',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            session.activeStoreName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (session.canManageOperators)
                      TextButton.icon(
                        onPressed: _inviteOperator,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Add person'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<Map<String, dynamic>>(
                  future: _operatorsFor(session),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SpazaListSkeleton(
                        semanticsLabel: 'Loading store team',
                        itemCount: 3,
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(vertical: 8),
                      );
                    }
                    if (snapshot.hasError) {
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const Text('Could not load operators'),
                          subtitle: Text(_errorMessage(snapshot.error!)),
                          trailing: IconButton(
                            onPressed: () => setState(_refreshOperators),
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      );
                    }
                    final payload = snapshot.data ?? const {};
                    final operators = payload['operators'] as List? ?? const [];
                    final pendingInvites =
                        payload['pendingInvites'] as List? ?? const [];
                    final teamRows = <Widget>[
                      ...operators.whereType<Map>().map((item) {
                        final uid = item['uid']?.toString() ?? '';
                        final name =
                            item['displayName']?.toString() ?? 'Operator';
                        final isOwner = item['role'] == 'owner';
                        final isSelf =
                            uid == FirebaseAuth.instance.currentUser?.uid;
                        final last4 = item['phoneLast4']?.toString() ?? '';
                        return ListTile(
                          minVerticalPadding: 10,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(name),
                          subtitle: Text(
                            '${item['role']}${last4.isEmpty ? '' : ' · •••• $last4'}',
                          ),
                          trailing: session.canManageOperators &&
                                  !isOwner &&
                                  !isSelf
                              ? IconButton(
                                  tooltip: 'Remove operator',
                                  onPressed: () => _removeOperator(uid, name),
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                )
                              : null,
                        );
                      }),
                      if (pendingInvites.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Pending invitations'),
                          ),
                        ),
                        ...pendingInvites.whereType<Map>().map((item) {
                          final inviteId = item['inviteId']?.toString() ?? '';
                          final last4 = item['phoneLast4']?.toString() ?? '';
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.schedule_outlined),
                            ),
                            title: Text('•••• $last4'),
                            subtitle:
                                Text('${item['role']} · awaiting sign-in'),
                            trailing: IconButton(
                              tooltip: 'Cancel invitation',
                              onPressed: () => _cancelInvite(inviteId),
                              icon: const Icon(Icons.close),
                            ),
                          );
                        }),
                      ],
                    ];
                    return Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(SpazaRadius.surface),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        children: teamRows.isEmpty
                            ? [
                                const ListTile(
                                  leading: Icon(Icons.people_outline),
                                  title: Text('No team members yet'),
                                ),
                              ]
                            : teamRows,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StoreAccessStateCard extends StatelessWidget {
  const _StoreAccessStateCard({
    required this.loading,
    required this.connectionIssue,
    required this.onRetry,
  });

  final bool loading;
  final bool connectionIssue;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.cloud_off_outlined,
                      color: theme.colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loading
                        ? 'Loading your stores'
                        : connectionIssue
                            ? 'Stores unavailable'
                            : 'No stores available',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    loading
                        ? 'Connecting securely…'
                        : connectionIssue
                            ? 'Check your connection and try again.'
                            : 'Ask a store owner to add you.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!loading)
              IconButton(
                tooltip: 'Try again',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(StoreRole role) {
  switch (role) {
    case StoreRole.owner:
      return 'Owner';
    case StoreRole.admin:
      return 'Admin';
    case StoreRole.operator:
      return 'Operator';
  }
}

class _ActiveStoreCard extends StatelessWidget {
  const _ActiveStoreCard({required this.session});

  final StoreSession session;

  @override
  Widget build(BuildContext context) => ActiveStoreSummary(
        storeName: session.activeStoreName,
        role: session.activeStore == null
            ? null
            : _roleLabel(session.activeStore!.role),
      );
}

/// Read-only context above the store and team management actions.
class ActiveStoreSummary extends StatelessWidget {
  const ActiveStoreSummary({super.key, required this.storeName, this.role});

  final String storeName;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(SpazaSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 36,
            child: Icon(SpazaIcons.shop, size: 22),
          ),
          const SizedBox(width: SpazaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == null ? 'Active store' : 'Active store · $role',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SpazaSpace.xs),
                Text(
                  storeName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
