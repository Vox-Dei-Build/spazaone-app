import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';

/// One scaffold to rule the transaction/sale forms (Add Credit, Add Payment,
/// Edit Transaction, Add Sale, Edit Sale).
///
/// Replaces the per-file reinventions audited against
/// `delivery-pod.md` / `design-quality-gate.md`. Provides:
///
/// - sticky bottom CTA bar (primary always reachable when keyboard is up);
/// - real disabled state when [isLoading] (no `() {}` no-op fakery);
/// - inline progress indicator that doesn't sit on top of the label;
/// - optional secondary `Cancel` action;
/// - optional destructive `Delete` action (AppBar trailing icon);
/// - unsaved-changes guard via `PopScope` when [isDirty] is true;
/// - keyboard-dismiss on outside tap;
/// - consistent horizontal padding matching the rest of the app.
///
/// The form body is supplied by the caller; the scaffold owns layout,
/// CTA placement, and the navigation/destructive flows.
class TransactionFormScaffold extends StatelessWidget {
  const TransactionFormScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.body,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.scaffoldKey,
    this.primaryActionIcon,
    this.primaryActionColor,
    this.totalLabel,
    this.isLoading = false,
    this.isDirty = false,
    this.onDelete,
    this.deleteConfirmTitle,
    this.deleteConfirmMessage,
    this.unsavedChangesTitle = 'Discard changes?',
    this.unsavedChangesMessage =
        'You have unsaved changes. Leaving now will discard them.',
  });

  /// Optional Scaffold key. Passed through onto the underlying
  /// [Scaffold] so callers can show SnackBars / open drawers from
  /// outside the form's BuildContext (e.g. the shared
  /// `TransactionViewModel.scaffoldKey`, which is dereferenced from the
  /// product-search delegate's tap handlers). Without this, the picker's
  /// onTap silently no-ops in release builds because the orphaned key's
  /// `currentContext` is null and `addProduct(...)` throws on the null
  /// check inside an async callback.
  final GlobalKey<ScaffoldState>? scaffoldKey;


  /// AppBar title.
  final String title;

  /// Form key — required so the scaffold can run [FormState.validate]
  /// before invoking the primary action. This is the fix for the
  /// audited Add Payment / Edit Transaction screens that shipped with a
  /// `Form` and no key.
  final GlobalKey<FormState> formKey;

  /// Form fields. Will be wrapped in a `Form`, scrollable, with the
  /// scaffold's standard horizontal padding.
  final Widget body;

  /// Primary CTA label (e.g. "Add Credit", "Update Sale").
  final String primaryActionLabel;

  /// Primary CTA handler. Only called after `formKey.currentState.validate()`
  /// returns true and when [isLoading] is false.
  final VoidCallback onPrimaryAction;

  /// Optional icon for the primary CTA.
  final IconData? primaryActionIcon;

  /// Primary CTA background colour. Defaults to [kPrimaryColor].
  final Color? primaryActionColor;

  /// Optional summary line shown above the CTA (e.g. "Total: R 123.45").
  final Widget? totalLabel;

  /// When true, the CTA is rendered in a disabled style and is
  /// non-interactive; an inline spinner is shown alongside.
  final bool isLoading;

  /// When true, backing out of the screen prompts a discard confirmation.
  final bool isDirty;

  /// When supplied, shows a delete icon in the AppBar that runs a
  /// destructive confirm dialog before invoking the callback.
  final Future<void> Function()? onDelete;

  /// Title for the delete confirmation dialog.
  final String? deleteConfirmTitle;

  /// Message for the delete confirmation dialog.
  final String? deleteConfirmMessage;

  final String unsavedChangesTitle;
  final String unsavedChangesMessage;

  Future<bool> _confirmDiscard(BuildContext context) async {
    if (!isDirty) return true;
    return ConfirmDialog.showDestructive(
      context,
      title: unsavedChangesTitle,
      message: unsavedChangesMessage,
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard(context);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          key: scaffoldKey,
          appBar: CustomAppBar(
            title: title,
            trailing: onDelete == null
                ? null
                : IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: isLoading
                        ? null
                        : () async {
                            final confirmed =
                                await ConfirmDialog.showDestructive(
                              context,
                              title: deleteConfirmTitle ?? 'Delete?',
                              message: deleteConfirmMessage ??
                                  'This action cannot be undone.',
                              confirmLabel: 'Delete',
                            );
                            if (confirmed) {
                              await onDelete!();
                            }
                          },
                  ),
          ),
          // PAS-UX-17: sticky CTA lives in the bottomNavigationBar slot
          // (same pattern as PayLaterActionBar) so it is laid out as a
          // single rigid surface measured independently of the body. The
          // previous Column(Expanded, _StickyActionBar) body-anchored
          // layout caused the button to visibly float/jump as the
          // keyboard opened and closed (and on every outside-tap
          // unfocus), because the body shrank/grew on each resize and
          // dragged the CTA with it. The bottomNavigationBar slot still
          // rises above the keyboard but moves as one anchored bar.
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: LayoutConstants.padding10Horizontal,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    bottom: LayoutConstants.spaceLg,
                  ),
                  child: body,
                ),
              ),
            ),
          ),
          bottomNavigationBar: _StickyActionBar(
            totalLabel: totalLabel,
            primaryActionLabel: primaryActionLabel,
            primaryActionIcon: primaryActionIcon,
            primaryActionColor: primaryActionColor ?? kPrimaryColor,
            isLoading: isLoading,
            onPrimaryAction: () {
              if (isLoading) return;
              if (formKey.currentState?.validate() ?? false) {
                onPrimaryAction();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _StickyActionBar extends StatelessWidget {
  const _StickyActionBar({
    required this.totalLabel,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.primaryActionColor,
    required this.isLoading,
    required this.onPrimaryAction,
  });

  final Widget? totalLabel;
  final String primaryActionLabel;
  final IconData? primaryActionIcon;
  final Color primaryActionColor;
  final bool isLoading;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final disabled = isLoading;
    final color = disabled ? Colors.grey.shade400 : primaryActionColor;

    // Rendered into Scaffold.bottomNavigationBar — own the Material
    // surface + safe-area inset so it visually anchors like
    // PayLaterActionBar and respects the device gesture bar.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            LayoutConstants.spaceMd,
            LayoutConstants.spaceSm,
            LayoutConstants.spaceMd,
            LayoutConstants.spaceSm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totalLabel != null) ...[
                Center(child: totalLabel!),
                const SizedBox(height: LayoutConstants.spaceSm),
              ],
              Semantics(
                button: true,
                enabled: !disabled,
                label: primaryActionLabel,
                child: SizedBox(
                  height: LayoutConstants.minTouchTarget + 4,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: disabled ? null : onPrimaryAction,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(primaryActionIcon ?? Icons.check),
                    label: Text(
                      primaryActionLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
