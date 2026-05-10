import 'package:flutter/material.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/utils/auth_util.dart';

/// PAS-UX-09: single source of truth for launching the Run Promotion
/// flow.
///
/// The audit found three sites that each rolled their own
/// "are any templates approved?" check before pushing
/// `RunPromotionPage`, and the predicates had drifted:
///
///  - `promotions_page.dart` FAB and intent-handler used
///    `whatsapp.approvalStatus == 'approved' || whatsapp.approved == true`
///    in one spot, and the same plus an `sms.approved == true` legacy
///    leg in another.
///  - `sales.dart` FAB used
///    `whatsapp.approved == true || sms.approved == true` — i.e. it
///    completely missed the canonical `approvalStatus` string and
///    would (silently) refuse to launch for any template created
///    after the new field was introduced.
///
/// Three predicates means at least two are wrong; in practice all
/// three were drift from `templateStatusOf` in
/// `template_status.dart`, which is the canonical reader the rest
/// of the Promote surface already uses.
///
/// `RunPromotionLauncher.launch` is the single entry point. It:
///
///   - reads template approval through `templateStatusOf` so future
///     status-string changes only need to update one file,
///   - routes to the no-approved-templates dialog when nothing is
///     usable, with an optional callback to switch the host UI to
///     the Templates view,
///   - pushes `RunPromotionPage` and refreshes the report list on
///     return.
class RunPromotionLauncher {
  const RunPromotionLauncher._();

  /// Returns true if any template in [templates] is approved and
  /// therefore usable for sending.
  ///
  /// Delegates to `templateStatusOf` so we honour the legacy
  /// `approved == true` boolean alongside the canonical
  /// `approvalStatus == 'approved'` string.
  static bool hasApprovedTemplate(List<Map<String, dynamic>> templates) {
    return templates.any((t) => templateStatusOf(t).isUsable);
  }

  /// Launches the Run Promotion flow.
  ///
  /// If no templates are approved, shows the standard "No Approved
  /// Templates" dialog. When the user taps "Go to Templates",
  /// [onGoToTemplates] is invoked so the host can change tabs/views
  /// to land them on the Templates surface.
  ///
  /// On successful return from `RunPromotionPage`,
  /// [PromotionsViewModel.fetchPromotionsReports] is called so the
  /// report list reflects the new send.
  ///
  /// PAS-UX-06: [initialTemplateId] pre-selects a template on the
  /// first step. Used by the Templates tab "Use this template" CTA
  /// so a merchant browsing templates can jump straight into the
  /// send flow without having to re-pick the template they were
  /// just looking at.
  static Future<void> launch(
    BuildContext context, {
    required PromotionsViewModel viewModel,
    VoidCallback? onGoToTemplates,
    String? initialTemplateId,
  }) async {
    // PAS-UX-14: anonymous gate at the screen edge. Promote is one
    // of three sensitive surfaces flagged by the audit (along with
    // Add Payment / Add Credit) where an anonymous user could
    // navigate the entire flow only to be bounced at submit. We
    // prompt for registration before any further work happens.
    final passed = await isAnonymousGate(context);
    if (!passed) return;
    if (!context.mounted) return;

    if (!hasApprovedTemplate(viewModel.templates)) {
      await _showNoApprovedDialog(
        context,
        onGoToTemplates: onGoToTemplates,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunPromotionPage(
          initialTemplateId: initialTemplateId,
        ),
      ),
    );
    if (!context.mounted) return;
    await viewModel.fetchPromotionsReports();
  }

  static Future<void> _showNoApprovedDialog(
    BuildContext context, {
    VoidCallback? onGoToTemplates,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No approved templates'),
        content: const Text(
          'You need at least one approved template before you can run '
          'a promotion. Head to the Templates tab to create or submit '
          'one.',
        ),
        actions: [
          if (onGoToTemplates != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onGoToTemplates();
              },
              child: const Text('Go to Templates'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
