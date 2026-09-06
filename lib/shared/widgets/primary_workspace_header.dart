import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/settings/setup/merchant_setup_page.dart';
import 'package:pasella/pages/settings/setup/your_shop_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';
import 'package:pasella/shared/widgets/shop_link_action.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';
import 'package:provider/provider.dart';

/// Shared app chrome for the three primary Spaza One workspaces.
///
/// Global controls have one stable hierarchy on Customers, Products, and
/// Sales. Page-specific search/help actions belong beside their local tabs,
/// not in this header.
class PrimaryWorkspaceHeader extends StatelessWidget {
  const PrimaryWorkspaceHeader({
    super.key,
    required this.shareSource,
  });

  final String shareSource;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<StoreSession>();
    final storeName = session.activeStoreName;
    final storeId = session.storeId;

    return ResponsiveWorkspaceHeaderLayout(
      appHeader: const PageHeader(),
      storeHeader: _SetupAwareWorkspaceHeader(
        storeId: storeId,
        storeName: storeName,
        onManageStorePressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const YourShopPage()),
          );
        },
        onSetupPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MerchantSetupPage(),
            ),
          );
        },
        onShopPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SharePage(source: shareSource),
            ),
          );
        },
      ),
    );
  }
}

class _SetupAwareWorkspaceHeader extends StatefulWidget {
  const _SetupAwareWorkspaceHeader({
    required this.storeId,
    required this.storeName,
    required this.onManageStorePressed,
    required this.onSetupPressed,
    required this.onShopPressed,
  });

  final String storeId;
  final String storeName;
  final VoidCallback onManageStorePressed;
  final VoidCallback onSetupPressed;
  final VoidCallback onShopPressed;

  @override
  State<_SetupAwareWorkspaceHeader> createState() =>
      _SetupAwareWorkspaceHeaderState();
}

class _SetupAwareWorkspaceHeaderState
    extends State<_SetupAwareWorkspaceHeader> {
  late Stream<MerchantSetupState> _setup;

  @override
  void initState() {
    super.initState();
    _setup = watchMerchantSetup(widget.storeId);
  }

  @override
  void didUpdateWidget(covariant _SetupAwareWorkspaceHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      _setup = watchMerchantSetup(widget.storeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MerchantSetupState>(
      stream: _setup,
      initialData: const MerchantSetupState.loading(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const MerchantSetupState.loading();
        final progress = state.loading || state.isComplete
            ? null
            : '${state.completedSteps}/${state.totalSteps} setup';
        return WorkspaceHeaderBar(
          storeName: widget.storeName,
          setupProgressLabel: progress,
          onStorePressed: workspaceShouldOpenSetup(state)
              ? widget.onSetupPressed
              : widget.onManageStorePressed,
          onShopPressed: widget.onShopPressed,
        );
      },
    );
  }
}

@visibleForTesting
bool workspaceShouldOpenSetup(MerchantSetupState state) =>
    !state.loading && !state.isComplete;

/// Compact store context plus the active storefront action.
///
/// Kept public so narrow-screen and dynamic-type behaviour can be exercised
/// without constructing Firebase-backed page state in widget tests.
class WorkspaceHeaderBar extends StatelessWidget {
  const WorkspaceHeaderBar({
    super.key,
    required this.storeName,
    required this.onStorePressed,
    required this.onShopPressed,
    this.showStoreContext = true,
    this.setupProgressLabel,
  });

  final String? storeName;
  final VoidCallback? onStorePressed;
  final VoidCallback onShopPressed;
  final bool showStoreContext;
  final String? setupProgressLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final suppliedStoreName = storeName?.trim() ?? '';
    final resolvedStoreName =
        suppliedStoreName.isEmpty ? 'Your store' : suppliedStoreName;
    final canOpenStores = onStorePressed != null;
    final showProgress = setupProgressLabel != null;
    final compactLandscape = usesCompactLandscapeLayout(context);
    final stackProgress =
        showProgress && MediaQuery.textScalerOf(context).scale(11) >= 18;
    final visibleProgressLabel = compactLandscape && !stackProgress
        ? setupProgressLabel?.replaceFirst(' setup', '')
        : setupProgressLabel;

    if (!showStoreContext) {
      return Align(
        alignment: Alignment.centerRight,
        child: ShopLinkAction(
          key: const ValueKey('workspace-shop-action'),
          onPressed: onShopPressed,
        ),
      );
    }

    final storeContents = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compactLandscape ? 8 : 12),
        child: Row(
          children: [
            Icon(
              SpazaIcons.shop,
              color: colors.onSurfaceVariant,
              size: compactLandscape ? 18 : 20,
            ),
            SizedBox(width: compactLandscape ? 6 : LayoutConstants.spaceSm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resolvedStoreName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (stackProgress)
                    Text(
                      setupProgressLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kTertiaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            if (canOpenStores) ...[
              const SizedBox(width: LayoutConstants.spaceXs),
              if (showProgress && !stackProgress) ...[
                Container(
                  key: const ValueKey('workspace-setup-progress'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: kTertiaryColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    visibleProgressLabel!,
                    style: const TextStyle(
                      color: kTertiaryColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: LayoutConstants.spaceXs),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: compactLandscape ? 18 : 20,
              ),
            ],
          ],
        ),
      ),
    );
    final storeSurface = Material(
      color: SpazaColors.subtle,
      borderRadius: BorderRadius.circular(SpazaRadius.control),
      child: canOpenStores
          ? InkWell(
              onTap: onStorePressed,
              borderRadius: BorderRadius.circular(SpazaRadius.control),
              child: storeContents,
            )
          : storeContents,
    );

    final storeAction = Semantics(
      key: const ValueKey('workspace-store-action'),
      button: canOpenStores,
      label: canOpenStores
          ? 'Current store, $resolvedStoreName. Open your shop${setupProgressLabel == null ? '' : '. $setupProgressLabel complete'}'
          : 'Current store, $resolvedStoreName',
      onTap: onStorePressed,
      excludeSemantics: true,
      child: canOpenStores
          ? Tooltip(message: 'Your shop', child: storeSurface)
          : storeSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final needsTwoRows = MediaQuery.textScalerOf(context).scale(13) >= 23 ||
            !compactLandscape && constraints.maxWidth < 300;
        if (needsTwoRows) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              storeAction,
              const SizedBox(height: LayoutConstants.spaceSm),
              ShopLinkAction(
                key: const ValueKey('workspace-shop-action'),
                storeName: resolvedStoreName,
                fillWidth: true,
                compact: compactLandscape,
                onPressed: onShopPressed,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: storeAction),
            const SizedBox(width: LayoutConstants.spaceSm),
            ShopLinkAction(
              key: const ValueKey('workspace-shop-action'),
              storeName: resolvedStoreName,
              compact: compactLandscape,
              onPressed: onShopPressed,
            ),
          ],
        );
      },
    );
  }
}
