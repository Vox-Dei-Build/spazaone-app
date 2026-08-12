import 'package:flutter/material.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';

class TopUpTab extends StatelessWidget {
  const TopUpTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final WalletViewModel walletVM = WalletViewModel();
    final tutorialUrl =
        TutorialConfig.getTutorialUrl(TutorialConfig.TUTORIAL_WALLET);

    return BillingTopUpMenu(
      showOnline: FeatureFlags.enableTopUpPaystack,
      showHelp: tutorialUrl.isNotEmpty,
      onOnline: () => walletVM.openPaystackForm(context),
      onHelp: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LoomVideoPage(
              loomUrl: tutorialUrl,
              title: 'How wallet top-ups work',
            ),
          ),
        );
      },
    );
  }
}

/// Compact, testable presentation for Billing's Top Up landing page.
///
/// The actions deliberately use the same icon-first, full-height cards as the
/// Account tab. Billing already explains the balance above the tabs, so this
/// view only presents the next actions and does not repeat that information.
class BillingTopUpMenu extends StatelessWidget {
  const BillingTopUpMenu({
    super.key,
    required this.showOnline,
    required this.showHelp,
    required this.onOnline,
    required this.onHelp,
  });

  final bool showOnline;
  final bool showHelp;
  final VoidCallback onOnline;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final actions = <_TopUpAction>[
      if (showOnline)
        _TopUpAction(
          key: const ValueKey('billing-top-up-online'),
          icon: Icons.credit_card_outlined,
          title: 'Pay online',
          color: Colors.blue.shade700,
          onTap: onOnline,
        ),
      if (showHelp)
        _TopUpAction(
          key: const ValueKey('billing-top-up-help'),
          icon: Icons.play_circle_outline_rounded,
          title: 'How top-ups work',
          color: Colors.orange.shade800,
          onTap: onHelp,
        ),
    ];

    if (actions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Online Campaign Credit top-ups are temporarily unavailable. No manual WhatsApp top-up is required.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      key: const ValueKey('billing-top-up-dashboard'),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            Expanded(
              child: _TopUpActionTile(action: actions[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopUpAction {
  const _TopUpAction({
    required this.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
}

class _TopUpActionTile extends StatelessWidget {
  const _TopUpActionTile({required this.action});

  final _TopUpAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: action.key,
      color: action.color.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: action.color.withValues(alpha: .16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(action.icon, size: 25, color: action.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: action.color),
            ],
          ),
        ),
      ),
    );
  }
}
