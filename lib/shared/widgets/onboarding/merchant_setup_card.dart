import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

/// Callbacks the merchant setup card fires when the user taps into a step.
///
/// Grouped into one immutable struct so the card takes a single
/// argument instead of five positional callbacks (which historically
/// drifted in order between call sites).
class MerchantSetupActions {
  const MerchantSetupActions({
    required this.onAddCustomer,
    required this.onAddProduct,
    required this.onChooseWhatsAppProducts,
    required this.onOpenOrderingLink,
    required this.onOpenBanking,
    required this.onCreateTemplate,
  });

  final VoidCallback onAddCustomer;
  final VoidCallback onAddProduct;
  final VoidCallback onChooseWhatsAppProducts;
  final VoidCallback onOpenOrderingLink;
  final VoidCallback onOpenBanking;

  /// Opens Marketing so Spaza One can prepare the reusable product-promotion
  /// message automatically. The callback name is retained for source
  /// compatibility with older call sites.
  final VoidCallback onCreateTemplate;
}

/// The merchant setup card.
///
/// Walks a fresh merchant through the six things that need to be true before
/// their shop can trade, order, get paid, and market. It lives in Settings →
/// Shop Setup so the daily Customers surface remains focused:
///
///   1. Add first customer
///   2. Add first product
///   3. Choose WhatsApp-listed products
///   4. Ordering link ready
///   5. Payout details added
///   6. Promotion template approved
///
/// Marketing (steps 3, 4, 6) is deliberately gated behind having at
/// least one product — the disabled rows still communicate "these
/// exist and are next" without offering a dead-end tap.
///
/// Once every step is done, the card swaps to [_ShopLinkPanel] — a
/// share-and-copy panel for the WhatsApp ordering link. The panel is
/// dismissible per-user via Hive; a fresh install re-shows it.
///
/// Reads its data from a single [Stream<MerchantSetupState>] provided
/// by [watchMerchantSetup]. The nested six-`StreamBuilder` cascade
/// that used to live here is now one call.
///
/// Callers that already own a [MerchantSetupState] can pass it directly via
/// [state] to avoid opening a second set of Firestore listeners.
class MerchantSetupCard extends StatefulWidget {
  /// Build a card that owns its own Firestore subscription.
  const MerchantSetupCard({
    super.key,
    required this.userId,
    required this.actions,
    this.allowCompletedLinkDismissal = true,
  })  : _stateOverride = null,
        state = null;

  /// Build a card from a state supplied by a parent widget. Nothing
  /// is subscribed internally; the parent owns the lifecycle. Used by
  /// [CustomerTab] to share one subscription with the growth-nudge
  /// gate.
  const MerchantSetupCard.fromState({
    super.key,
    required this.userId,
    required this.actions,
    required MerchantSetupState this.state,
    this.allowCompletedLinkDismissal = true,
  }) : _stateOverride = null;

  /// Test-only: build a card that subscribes to a caller-supplied
  /// stream instead of the Firestore-backed [watchMerchantSetup].
  const MerchantSetupCard.forTesting({
    super.key,
    required this.userId,
    required this.actions,
    required Stream<MerchantSetupState> stateStream,
    this.allowCompletedLinkDismissal = true,
  })  : _stateOverride = stateStream,
        state = null;

  final String userId;
  final MerchantSetupActions actions;
  final MerchantSetupState? state;
  final Stream<MerchantSetupState>? _stateOverride;

  /// Whether the completed shop-link panel can be hidden from this surface.
  ///
  /// Embedded nudges may be dismissed, but dedicated destinations such as
  /// Settings → Shop Setup must always retain useful content.
  final bool allowCompletedLinkDismissal;

  @visibleForTesting
  static const shopLinkDismissedHiveKeyPrefix = 'merchant_setup_shop_link:';

  @override
  State<MerchantSetupCard> createState() => _MerchantSetupCardState();
}

class _MerchantSetupCardState extends State<MerchantSetupCard> {
  static const _boxName = 'appBox';

  late String _shopLinkDismissedKey;
  Stream<MerchantSetupState>? _stream;
  bool _shopLinkDismissed = false;

  @override
  void initState() {
    super.initState();
    _resolveKeyAndStream();
    _readShopLinkDismissed();
  }

  @override
  void didUpdateWidget(covariant MerchantSetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget._stateOverride != widget._stateOverride ||
        oldWidget.state != widget.state) {
      _resolveKeyAndStream();
      _readShopLinkDismissed();
    }
  }

  void _resolveKeyAndStream() {
    _shopLinkDismissedKey =
        '${MerchantSetupCard.shopLinkDismissedHiveKeyPrefix}${widget.userId}';
    if (widget.state != null) {
      // Parent-managed state; no subscription needed.
      _stream = null;
    } else {
      _stream = widget._stateOverride ?? watchMerchantSetup(widget.userId);
    }
  }

  void _readShopLinkDismissed() {
    if (widget.userId.isEmpty) {
      _shopLinkDismissed = false;
      return;
    }
    // Guard the Hive read so a missing box (e.g. widget tests that
    // don't initialise Hive, or a pre-init render path in production)
    // doesn't crash the card. Falling back to "not dismissed" is the
    // safer default: at worst the merchant sees the shop link panel
    // for one extra render.
    try {
      _shopLinkDismissed = Hive.box(_boxName)
          .get(_shopLinkDismissedKey, defaultValue: false) as bool;
    } catch (_) {
      _shopLinkDismissed = false;
    }
  }

  Future<void> _hideShopLink() async {
    try {
      await Hive.box(_boxName).put(_shopLinkDismissedKey, true);
    } catch (_) {
      // If Hive isn't ready we can't persist dismissal. Still update
      // the in-memory flag so the current session honours the tap.
    }
    if (!mounted) return;
    setState(() => _shopLinkDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) return const SizedBox.shrink();

    if (widget.state != null) {
      return _wrap(widget.state!);
    }

    return StreamBuilder<MerchantSetupState>(
      stream: _stream,
      initialData: const MerchantSetupState.loading(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const MerchantSetupState.loading();
        return _wrap(state);
      },
    );
  }

  Widget _wrap(MerchantSetupState state) {
    if (widget.allowCompletedLinkDismissal &&
        state.isComplete &&
        _shopLinkDismissed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LayoutConstants.spaceSm,
        LayoutConstants.spaceSm,
        LayoutConstants.spaceSm,
        LayoutConstants.spaceMd,
      ),
      child: _MerchantSetupSurface(
        state: state,
        actions: widget.actions,
        onHideShopLink:
            widget.allowCompletedLinkDismissal ? _hideShopLink : null,
      ),
    );
  }
}

/// The card chrome + body switcher. Kept separate from
/// [MerchantSetupCard] so it can be unit-tested with a fake state
/// without needing Firestore or Hive.
class _MerchantSetupSurface extends StatelessWidget {
  const _MerchantSetupSurface({
    required this.state,
    required this.actions,
    required this.onHideShopLink,
  });

  final MerchantSetupState state;
  final MerchantSetupActions actions;
  final VoidCallback? onHideShopLink;

  @override
  Widget build(BuildContext context) {
    if (state.loading) return const _SetupSkeleton();
    if (state.isComplete) {
      return _ShopLinkPanel(
        shopName: state.shopName,
        orderingUrl: state.orderingUrl,
        orderingCode: state.orderingCode,
        fallbackText: state.fallbackText,
        onOpenOrderingLink: actions.onOpenOrderingLink,
        onHide: onHideShopLink,
      );
    }
    return _SetupPanel(state: state, actions: actions);
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

class _SetupSkeleton extends StatelessWidget {
  const _SetupSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final highlightColor = theme.colorScheme.surface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.spaceLg),
        child: Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: LayoutConstants.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 140,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 10,
                          width: 90,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: LayoutConstants.spaceLg),
              Container(
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: LayoutConstants.spaceSm),
                      Expanded(
                        child: Container(height: 10, color: Colors.white),
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

// ---------------------------------------------------------------------------
// Setup panel (incomplete)
// ---------------------------------------------------------------------------

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({required this.state, required this.actions});

  final MerchantSetupState state;
  final MerchantSetupActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final steps = _buildSteps(state, actions);
    final completed = steps.where((s) => s.done).length;
    final actionable = steps.where((s) => !s.done && s.action != null).toList();
    final nextStep = actionable.isEmpty ? null : actionable.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SetupHeader(
              completed: completed,
              total: state.totalSteps,
            ),
            const SizedBox(height: LayoutConstants.spaceMd),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: state.totalSteps == 0 ? 0 : completed / state.totalSteps,
                minHeight: 8,
                backgroundColor: primary.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            if (nextStep != null) ...[
              const SizedBox(height: LayoutConstants.spaceLg),
              _NextActionPanel(step: nextStep),
            ],
            const SizedBox(height: LayoutConstants.spaceLg),
            // The current action is already presented prominently above.
            // Keep the checklist useful without repeating the same title and
            // CTA twice in one card.
            for (final step in steps.where((step) => step != nextStep))
              _StepRow(step: step),
          ],
        ),
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.rocket_launch_outlined,
            color: primary,
            size: 22,
          ),
        ),
        const SizedBox(width: LayoutConstants.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set up your shop',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$completed of $total done',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.75,
                  ),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NextActionPanel extends StatelessWidget {
  const _NextActionPanel({required this.step});

  final _SetupStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(LayoutConstants.spaceMd),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(step.icon, color: primary, size: 22),
              const SizedBox(width: LayoutConstants.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Up next',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.actionTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.actionBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LayoutConstants.spaceMd),
          ElevatedButton(
            onPressed: step.action,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize:
                  const Size.fromHeight(LayoutConstants.minTouchTarget),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(step.actionLabel!),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _SetupStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isEnabled = !step.done && step.action != null;
    final iconColor = step.done
        ? primary
        : (isEnabled ? theme.colorScheme.onSurface : Colors.grey.shade500);
    final titleColor = step.done
        ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)
        : theme.textTheme.bodyMedium?.color;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: LayoutConstants.spaceSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            step.done ? Icons.check_circle : step.icon,
            color: iconColor,
            size: 22,
          ),
          const SizedBox(width: LayoutConstants.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.rowTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.rowBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.25,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.75,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isEnabled)
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
        ],
      ),
    );

    if (!isEnabled) return row;

    return InkWell(
      onTap: step.action,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

// ---------------------------------------------------------------------------
// Shop link panel (all steps done)
// ---------------------------------------------------------------------------

class _ShopLinkPanel extends StatelessWidget {
  const _ShopLinkPanel({
    required this.shopName,
    required this.orderingUrl,
    required this.orderingCode,
    required this.fallbackText,
    required this.onOpenOrderingLink,
    required this.onHide,
  });

  final String shopName;
  final String orderingUrl;
  final String orderingCode;
  final String fallbackText;
  final VoidCallback onOpenOrderingLink;
  final VoidCallback? onHide;

  String get _copyValue {
    if (orderingUrl.isNotEmpty) return orderingUrl;
    if (orderingCode.isNotEmpty) return 'shop $orderingCode';
    return '';
  }

  String get _shareMessage {
    return [
      'You can order from $shopName on WhatsApp:',
      orderingUrl,
      '',
      'Open the link to place an order.',
      if (fallbackText.isNotEmpty) fallbackText,
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  Future<void> _copy(BuildContext context) async {
    if (_copyValue.isEmpty) {
      onOpenOrderingLink();
      return;
    }
    await Clipboard.setData(ClipboardData(text: _copyValue));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order link copied.')),
    );
  }

  Future<void> _share() async {
    if (_shareMessage.trim().isEmpty) {
      onOpenOrderingLink();
      return;
    }
    await Share.share(_shareMessage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final linkLabel =
        orderingUrl.isNotEmpty ? orderingUrl : 'shop $orderingCode';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    FontAwesomeIcons.whatsapp,
                    color: primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: LayoutConstants.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your shop link is ready',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Share it on WhatsApp so anyone can place an order.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onHide != null)
                  IconButton(
                    tooltip: 'Hide',
                    onPressed: onHide,
                    icon: const Icon(Icons.close),
                    constraints: const BoxConstraints(
                      minWidth: LayoutConstants.minTouchTarget,
                      minHeight: LayoutConstants.minTouchTarget,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: LayoutConstants.spaceMd),
            _LinkPreview(
              url: linkLabel,
              code: orderingCode,
              onCopy: () => _copy(context),
            ),
            const SizedBox(height: LayoutConstants.spaceMd),
            ElevatedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share on WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: theme.colorScheme.onPrimary,
                minimumSize:
                    const Size.fromHeight(LayoutConstants.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({
    required this.url,
    required this.code,
    required this.onCopy,
  });

  final String url;
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutConstants.spaceMd,
        vertical: LayoutConstants.spaceSm,
      ),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(width: LayoutConstants.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.spaceSm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                code,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Copy link',
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 20),
            constraints: const BoxConstraints(
              minWidth: LayoutConstants.minTouchTarget,
              minHeight: LayoutConstants.minTouchTarget,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step data
// ---------------------------------------------------------------------------

/// Immutable value class describing one step in the setup card.
///
/// Kept as a private data type (there is no reason for the outside
/// world to name it) but exposed via `@visibleForTesting` factories on
/// the state class if a widget test wants to peek at the ordering.
class _SetupStep {
  const _SetupStep({
    required this.rowTitle,
    required this.rowBody,
    required this.actionTitle,
    required this.actionBody,
    required this.done,
    required this.actionLabel,
    required this.action,
    required this.icon,
  });

  /// Row title in the "all six steps" list.
  final String rowTitle;

  /// Row supporting copy in the list.
  final String rowBody;

  /// Title of the "Up next" panel when this is the current step.
  /// Typically the imperative form of [rowTitle].
  final String actionTitle;

  /// Body copy of the "Up next" panel.
  final String actionBody;

  final bool done;
  final String? actionLabel;
  final VoidCallback? action;
  final IconData icon;
}

List<_SetupStep> _buildSteps(
  MerchantSetupState s,
  MerchantSetupActions a,
) {
  return [
    _SetupStep(
      done: s.hasCustomers,
      icon: Icons.person_add_alt_1_outlined,
      rowTitle:
          s.hasCustomers ? 'First customer saved' : 'Save your first customer',
      rowBody: s.hasCustomers
          ? 'Customer capture is ready for transactions, orders and follow-up.'
          : 'Save one real customer before setting up the rest.',
      actionTitle: 'Save your first customer',
      actionBody:
          'Save one real customer before setting up products, ordering or marketing.',
      actionLabel: 'Add customer',
      action: a.onAddCustomer,
    ),
    _SetupStep(
      done: s.hasProducts,
      icon: Icons.inventory_2_outlined,
      rowTitle:
          s.hasProducts ? 'First product added' : 'Add your first product',
      rowBody: s.hasProducts
          ? 'Products can now support item-level sales, stock and WhatsApp orders.'
          : 'Add the item customers buy most often before ordering or marketing.',
      actionTitle: 'Add your first product',
      actionBody:
          'Start with the item you sell most often. Products power sales detail and WhatsApp ordering.',
      actionLabel: 'Add product',
      action: a.onAddProduct,
    ),
    _SetupStep(
      done: s.hasListedProduct,
      icon: Icons.storefront_outlined,
      rowTitle: s.hasListedProduct
          ? 'WhatsApp products chosen'
          : 'Choose WhatsApp products',
      rowBody: s.hasListedProduct
          ? 'Customer-facing products are visible for WhatsApp orders.'
          : s.hasProducts
              ? 'Choose which products customers can order on WhatsApp.'
              : 'Available after a product exists.',
      actionTitle: 'Choose WhatsApp products',
      actionBody: 'Pick the products customers can see and order on WhatsApp.',
      actionLabel: s.hasProducts ? 'Choose products' : null,
      action: s.hasProducts ? a.onChooseWhatsAppProducts : null,
    ),
    _SetupStep(
      done: s.hasOrderingLink,
      icon: Icons.link_outlined,
      rowTitle:
          s.hasOrderingLink ? 'Ordering link ready' : 'Get your ordering link',
      rowBody: s.hasOrderingLink
          ? 'Your shop link is ready to share.'
          : s.hasProducts
              ? 'Generate the link customers use to place orders on WhatsApp.'
              : 'Available after a product exists.',
      actionTitle: 'Get your ordering link',
      actionBody:
          'Generate the WhatsApp link customers open to place an order.',
      actionLabel: s.hasOrderingLink
          ? 'View link'
          : s.hasProducts
              ? 'Get link'
              : null,
      action: s.hasProducts ? a.onOpenOrderingLink : null,
    ),
    _SetupStep(
      done: s.hasBank,
      icon: Icons.account_balance_outlined,
      rowTitle: s.hasBank ? 'Payout details added' : 'Add payout details',
      rowBody: s.hasBank
          ? 'Banking details are saved so we can pay you out.'
          : 'Add banking details so we can pay you out.',
      actionTitle: 'Add payout details',
      actionBody: 'Add banking details so we can pay you out.',
      actionLabel: 'Add bank',
      action: a.onOpenBanking,
    ),
    _SetupStep(
      done: s.hasApprovedTemplate,
      icon: Icons.campaign_outlined,
      rowTitle: s.hasApprovedTemplate
          ? 'WhatsApp promotions ready'
          : 'Prepare WhatsApp promotions',
      rowBody: s.hasApprovedTemplate
          ? 'Marketing messages are ready when you need them.'
          : s.hasProducts
              ? 'Spaza One prepares the reusable message and handles Meta approval.'
              : 'Available after a product exists.',
      actionTitle: 'Prepare WhatsApp promotions',
      actionBody:
          'Spaza One creates and submits the reusable product message for you.',
      actionLabel: s.hasProducts ? 'Open Marketing' : null,
      action: s.hasProducts ? a.onCreateTemplate : null,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Convenience constructor for the common Firebase-backed case
// ---------------------------------------------------------------------------

/// Convenience: builds a [MerchantSetupCard] for the currently signed-in
/// merchant. Returns an empty widget if no user is signed in.
///
/// Used by [CustomerTab] so callers don't have to look up the UID.
class MerchantSetupCardForCurrentUser extends StatelessWidget {
  const MerchantSetupCardForCurrentUser({
    super.key,
    required this.actions,
    this.firestoreOverride,
    this.authOverride,
  });

  final MerchantSetupActions actions;

  /// Test-only overrides. When set, the card is built against these
  /// instances instead of the process-wide singletons.
  final FirebaseFirestore? firestoreOverride;
  final FirebaseAuth? authOverride;

  @override
  Widget build(BuildContext context) {
    final auth = authOverride ?? FirebaseAuth.instance;
    final userId = authOverride == null
        ? StoreSession.instance.storeId
        : auth.currentUser?.uid ?? '';
    if (userId.isEmpty) return const SizedBox.shrink();
    return MerchantSetupCard(userId: userId, actions: actions);
  }
}
