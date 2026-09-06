import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';

/// One scaffold to rule the transaction/sale forms (Add Credit, Add Payment,
/// Edit Transaction, Add Sale, Edit Sale).
///
/// Replaces the per-file reinventions audited against
/// `delivery-pod.md` / `design-quality-gate.md`. Provides:
///
/// - bottom action bar that clears the keyboard and joins the form scroll on short screens;
/// - real disabled state when [isLoading] (no `() {}` no-op fakery);
/// - inline progress indicator that doesn't sit on top of the label;
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

  /// Primary CTA background colour. Defaults to the theme primary colour.
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

  void _submit() {
    if (isLoading) return;
    final errors = formKey.currentState?.validateGranularly();
    if (errors == null) return;
    if (errors.isEmpty) {
      onPrimaryAction();
      return;
    }
    // Bring the first invalid field into view after its error has been laid out.
    final firstError = errors.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!firstError.mounted) return;
      Scrollable.ensureVisible(
        firstError.context,
        alignment: .15,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height -
        media.viewInsets.bottom -
        media.padding.vertical -
        kToolbarHeight;
    // In landscape or with a tall keyboard, keep the form and action in one
    // scroll surface so a fixed footer cannot consume the entire viewport.
    final inlineAction = availableHeight < 240 ||
        (media.textScaler.scale(14) > 20 && availableHeight < 320);
    final actionBar = _StickyActionBar(
      totalLabel: totalLabel,
      primaryActionLabel: primaryActionLabel,
      primaryActionIcon: primaryActionIcon,
      primaryActionColor:
          primaryActionColor ?? Theme.of(context).colorScheme.primary,
      isLoading: isLoading,
      onPrimaryAction: _submit,
      embedded: inlineAction,
    );
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard(context);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        excludeFromSemantics: true,
        child: Scaffold(
          key: scaffoldKey,
          appBar: CustomAppBar(
            title: title,
            trailing: onDelete == null
                ? null
                : IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(SpazaIcons.delete, size: 22),
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
                            if (confirmed && context.mounted) await onDelete!();
                          },
                  ),
          ),
          body: SafeArea(
            bottom: inlineAction,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                key: const ValueKey('transaction-form-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body,
                    if (inlineAction) ...[
                      const SizedBox(height: 16),
                      actionBar,
                    ],
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: inlineAction
              ? null
              : Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: actionBar,
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
    required this.embedded,
  });

  final Widget? totalLabel;
  final String primaryActionLabel;
  final IconData? primaryActionIcon;
  final Color primaryActionColor;
  final bool isLoading;
  final VoidCallback onPrimaryAction;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Padding(
      padding:
          EdgeInsets.fromLTRB(embedded ? 0 : 16, 12, embedded ? 0 : 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (totalLabel != null) ...[
            DefaultTextStyle.merge(
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
              child: totalLabel!,
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            liveRegion: true,
            value: isLoading ? 'In progress' : null,
            child: FilledButton.icon(
              key: const ValueKey('transaction-primary-action'),
              style: FilledButton.styleFrom(
                backgroundColor: primaryActionColor,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SpazaRadius.control),
                ),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: isLoading ? null : onPrimaryAction,
              icon: isLoading
                  ? ExcludeSemantics(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Icon(primaryActionIcon ?? Icons.check_rounded, size: 20),
              label: Text(primaryActionLabel, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
    if (embedded) return content;
    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(top: false, child: content),
      ),
    );
  }
}
