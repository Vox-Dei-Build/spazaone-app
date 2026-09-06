import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// Compact entry into multi-store and team management.
///
/// The feature remains protected by the existing Remote Config gate; this
/// widget only improves discoverability once that gate is enabled.
class StoreWorkspaceCard extends StatelessWidget {
  const StoreWorkspaceCard({
    super.key,
    required this.activeStoreName,
    required this.storeCount,
    required this.role,
    required this.onTap,
    this.loading = false,
    this.connectionIssue = false,
  });

  final String activeStoreName;
  final int storeCount;
  final String role;
  final VoidCallback onTap;
  final bool loading;
  final bool connectionIssue;

  String get _roleLabel {
    final value = role.trim();
    if (value.isEmpty) return 'Owner';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final countLabel = loading && storeCount == 0
        ? 'Connecting…'
        : connectionIssue && storeCount == 0
            ? 'Tap to reconnect'
            : storeCount == 1
                ? '1 store'
                : '$storeCount stores';
    final detailLabel =
        storeCount == 0 ? countLabel : '$countLabel · $_roleLabel';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SpazaRadius.surface),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(SpazaRadius.surface),
                  ),
                  child: Icon(SpazaIcons.shop, color: primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stores & team',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeStoreName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detailLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (loading && storeCount == 0)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary,
                    ),
                  )
                else
                  Icon(
                    connectionIssue
                        ? Icons.cloud_off_outlined
                        : SpazaIcons.next,
                    color: connectionIssue
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
