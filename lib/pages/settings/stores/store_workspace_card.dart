import 'package:flutter/material.dart';

/// Premium, high-visibility entry into multi-store and team management.
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.storefront_outlined, color: primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STORES & TEAM',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        activeStoreName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                        : Icons.chevron_right_rounded,
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
