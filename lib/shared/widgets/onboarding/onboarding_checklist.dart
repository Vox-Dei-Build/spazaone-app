import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';

/// PAS-UX-02: first-session aha checklist.
///
/// The audit found that a new merchant landing in the app has no
/// scaffolded path through the four actions that produce the first
/// believable "aha" moment:
///
///   1. Add a product to your stock list.
///   2. Add a customer.
///   3. Record your first sale.
///   4. Get a WhatsApp template approved (so you can run a promotion).
///
/// Until each step is done, the merchant has no concrete reason to
/// trust the app, no data on any screen, and no way to evaluate
/// whether the product fits their workflow. Empty-state CTAs help
/// (PAS-UX-04 added them on Stock), but they're per-screen and the
/// merchant has to discover each one.
///
/// This widget surfaces all four steps as a single dismissible
/// banner on the default landing surface (Customers tab). Each tile:
///
///   - links to the screen that completes it,
///   - can be ticked off manually if the merchant has already done
///     the action through a different path,
///   - persists state per-user in Hive so the banner doesn't
///     re-appear once dismissed or once all four are done.
///
/// State key in Hive `appBox`:
///   `onboarding_checklist:<userId>` -> Map<String, bool>
/// The banner is hidden when:
///   - the user has explicitly dismissed it, OR
///   - at least three of the four items are marked done.
///
/// Hiding at 3/4 keeps the checklist focused on early activation.
/// Once a merchant has completed most of the setup, the banner stops
/// competing with the actual working surface.
///
/// Out of scope (deferred, see PAS-UX-02 audit notes):
///
///   - Auto-detecting completion from real data signals (would need
///     a stream watcher per dimension; the manual tick is the
///     pragmatic v1).
///   - Seeding pre-approved starter templates on registration: that
///     requires a backend approval-bypass for seeded templates, plus
///     Twilio template-id reservation. Tracked as a backend item.
///   - Empty-state CTAs across Contacts, Sales, Orders: PAS-UX-04
///     established the pattern on Stock; the other three surfaces
///     should follow but are deferred to keep this slice focused.
class OnboardingChecklist extends StatefulWidget {
  const OnboardingChecklist({
    super.key,
    required this.userId,
    required this.onAddProduct,
    required this.onAddCustomer,
    required this.onRecordSale,
    required this.onApproveTemplate,
  });

  final String userId;
  final VoidCallback onAddProduct;
  final VoidCallback onAddCustomer;
  final VoidCallback onRecordSale;
  final VoidCallback onApproveTemplate;

  @override
  State<OnboardingChecklist> createState() => _OnboardingChecklistState();
}

class _OnboardingChecklistState extends State<OnboardingChecklist> {
  static const _boxName = 'appBox';
  static const _dismissedSuffix = ':dismissed';

  static const _itemAddProduct = 'add_product';
  static const _itemAddCustomer = 'add_customer';
  static const _itemRecordSale = 'record_sale';
  static const _itemApproveTemplate = 'approve_template';

  late final String _stateKey =
      'onboarding_checklist:${widget.userId}';
  late final String _dismissedKey = '$_stateKey$_dismissedSuffix';

  late Map<String, bool> _state;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  void _loadState() {
    final box = Hive.box(_boxName);
    final raw = box.get(_stateKey);
    _state = <String, bool>{
      _itemAddProduct: false,
      _itemAddCustomer: false,
      _itemRecordSale: false,
      _itemApproveTemplate: false,
    };
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is bool && _state.containsKey(k)) {
          _state[k] = v;
        }
      }
    }
    _dismissed = box.get(_dismissedKey, defaultValue: false) as bool;
  }

  Future<void> _persist() async {
    final box = Hive.box(_boxName);
    await box.put(_stateKey, _state);
  }

  Future<void> _dismiss() async {
    final box = Hive.box(_boxName);
    await box.put(_dismissedKey, true);
    setState(() => _dismissed = true);
  }

  void _toggle(String key, bool value) {
    setState(() => _state[key] = value);
    _persist();
  }

  int get _completedCount => _state.values.where((v) => v).length;

  bool get _shouldHideChecklist => _completedCount >= 3;

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _shouldHideChecklist) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Get started with Pasella',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$_completedCount / 4',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: 'Hide',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _dismiss,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Four quick steps so the rest of the app has data '
              'to work with.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            _buildItem(
              key: _itemAddProduct,
              label: 'Add your first product',
              onTap: widget.onAddProduct,
            ),
            _buildItem(
              key: _itemAddCustomer,
              label: 'Add a customer',
              onTap: widget.onAddCustomer,
            ),
            _buildItem(
              key: _itemRecordSale,
              label: 'Record your first sale',
              onTap: widget.onRecordSale,
            ),
            _buildItem(
              key: _itemApproveTemplate,
              label: 'Approve a WhatsApp template',
              onTap: widget.onApproveTemplate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem({
    required String key,
    required String label,
    required VoidCallback onTap,
  }) {
    final done = _state[key] ?? false;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Manual tick / untick is intentional: see class doc on why
            // we don't auto-derive completion from real data signals
            // in this slice.
            Checkbox(
              value: done,
              onChanged: (v) => _toggle(key, v ?? false),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? Colors.grey : Colors.black87,
                ),
              ),
            ),
            if (!done)
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
