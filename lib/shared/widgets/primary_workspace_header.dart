import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/shop_link_action.dart';
import 'package:pasella/utils/feature_flags.dart';
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
    final storeName = context.watch<StoreSession>().activeStoreName;

    return ValueListenableBuilder<bool>(
      valueListenable: FeatureFlags.multiStoreOperatorsEnabled,
      builder: (context, multiStoreEnabled, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(),
            const SizedBox(height: LayoutConstants.spaceSm),
            WorkspaceHeaderBar(
              storeName: multiStoreEnabled ? storeName : null,
              showStoreContext: multiStoreEnabled,
              onStorePressed: multiStoreEnabled
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoreManagementPage(),
                        ),
                      );
                    }
                  : null,
              onShopPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SharePage(source: shareSource),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

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
  });

  final String? storeName;
  final VoidCallback? onStorePressed;
  final VoidCallback onShopPressed;
  final bool showStoreContext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final suppliedStoreName = storeName?.trim() ?? '';
    final resolvedStoreName =
        suppliedStoreName.isEmpty ? 'Your store' : suppliedStoreName;
    final canOpenStores = onStorePressed != null;

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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.storefront_outlined,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: LayoutConstants.spaceSm),
            Expanded(
              child: Text(
                resolvedStoreName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (canOpenStores) ...[
              const SizedBox(width: LayoutConstants.spaceXs),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
    final storeSurface = Material(
      color: colors.onSurface.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(14),
      child: canOpenStores
          ? InkWell(
              onTap: onStorePressed,
              borderRadius: BorderRadius.circular(14),
              child: storeContents,
            )
          : storeContents,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            key: const ValueKey('workspace-store-action'),
            button: canOpenStores,
            label: canOpenStores
                ? 'Current store, $resolvedStoreName. Open stores and team'
                : 'Current store, $resolvedStoreName',
            onTap: onStorePressed,
            excludeSemantics: true,
            child: canOpenStores
                ? Tooltip(message: 'Stores & team', child: storeSurface)
                : storeSurface,
          ),
        ),
        const SizedBox(width: LayoutConstants.spaceSm),
        ShopLinkAction(
          key: const ValueKey('workspace-shop-action'),
          storeName: resolvedStoreName,
          onPressed: onShopPressed,
        ),
      ],
    );
  }
}
