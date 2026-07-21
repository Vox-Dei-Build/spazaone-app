import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class StoreManagementPage extends StatefulWidget {
  const StoreManagementPage({super.key});

  @override
  State<StoreManagementPage> createState() => _StoreManagementPageState();
}

class _StoreManagementPageState extends State<StoreManagementPage> {
  Future<Map<String, dynamic>>? _operators;

  @override
  void initState() {
    super.initState();
    _refreshOperators();
  }

  void _refreshOperators() {
    _operators = StoreSession.instance.loadOperators();
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
        SnackBar(content: Text('${store.storeName} is ready.')),
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
    return Scaffold(
      appBar: const CustomAppBar(title: 'Stores & operators'),
      body: Consumer<StoreSession>(
        builder: (context, session, _) => RefreshIndicator(
          onRefresh: () async {
            await session.bootstrap();
            setState(_refreshOperators);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your stores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _createStore,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Add store'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...session.stores.map(
                (store) => Card(
                  child: RadioListTile<String>(
                    value: store.storeId,
                    groupValue: session.storeId,
                    onChanged: (value) {
                      if (value != null) _switchStore(value);
                    },
                    title: Text(store.storeName),
                    subtitle: Text('${store.role.name} access'),
                    secondary: const Icon(Icons.storefront_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Operators for ${session.activeStoreName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (session.canManageOperators)
                    OutlinedButton.icon(
                      onPressed: _inviteOperator,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<Map<String, dynamic>>(
                future: _operators,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
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
                  return Column(
                    children: [
                      ...operators.whereType<Map>().map((item) {
                        final uid = item['uid']?.toString() ?? '';
                        final name =
                            item['displayName']?.toString() ?? 'Operator';
                        final isOwner = item['role'] == 'owner';
                        final isSelf =
                            uid == FirebaseAuth.instance.currentUser?.uid;
                        final last4 = item['phoneLast4']?.toString() ?? '';
                        return Card(
                          child: ListTile(
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
                          ),
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
                          return Card(
                            child: ListTile(
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
                            ),
                          );
                        }),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
