import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/auth/widgets/logo_display.dart';
import 'package:pasella/widgets/private_region.dart';

/// A restrained, scrollable frame shared by each step of authentication.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.stepLabel,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final String? stepLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = keyboardVisible || constraints.maxHeight < 620;
            final horizontalPadding = constraints.maxWidth < 360 ? 20.0 : 28.0;
            return SingleChildScrollView(
              key: const ValueKey('auth-content-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: compact ? 18 : 30,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LogoDisplay(),
                      SizedBox(height: compact ? 36 : 88),
                      Container(
                        key: const ValueKey('auth-form-panel'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stepLabel != null) ...[
                              Text(
                                stepLabel!,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: SpazaColors.muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: SpazaColors.heading,
                                  fontSize: compact ? 28 : 32,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: SpazaColors.muted,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 32),
                            child,
                            if (footer != null) ...[
                              SizedBox(height: compact ? 28 : 44),
                              const Divider(),
                              const SizedBox(height: 18),
                              footer!,
                            ],
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    this.helper,
    this.enabled = true,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.maxLength,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final String? helper;
  final bool enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: SpazaColors.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  color: SpazaColors.ink,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: PrivateRegion(
            child: TextFormField(
              controller: controller,
              enabled: enabled,
              validator: validator,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              onFieldSubmitted: onSubmitted,
              maxLength: maxLength,
              style: Theme.of(context).textTheme.bodyLarge,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                hintText: hint,
                helperText: helper,
                helperMaxLines: 4,
                errorMaxLines: 5,
                counterText: maxLength == null ? null : '',
                filled: true,
                fillColor: SpazaColors.surface,
                border: border,
                enabledBorder: border,
                disabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: const BorderSide(
                    color: SpazaColors.heading,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel = 'Please wait…',
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: isLoading,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading) ...[
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  isLoading ? loadingLabel : label,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
}

/// The shared name inputs for both supported registration sequences.
class ProfileDetailsFields extends StatelessWidget {
  const ProfileDetailsFields({
    super.key,
    required this.nameController,
    required this.shopController,
    this.enabled = true,
    this.onSubmitted,
    this.limitShopName = false,
  });

  final TextEditingController nameController;
  final TextEditingController shopController;
  final bool enabled;
  final VoidCallback? onSubmitted;
  final bool limitShopName;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthField(
            label: 'Full name',
            hint: 'e.g. Thandi Mokoena',
            controller: nameController,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 16),
          AuthField(
            label: 'Business name',
            hint: 'e.g. The Corner Shop',
            helper: 'Shown on your receipts and customer messages.',
            controller: shopController,
            enabled: enabled,
            maxLength: limitShopName ? 40 : null,
            textCapitalization: TextCapitalization.words,
            textInputAction: onSubmitted == null
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.isEmpty) return 'Enter your business name';
              if (name.length < 2) return 'Business name is too short';
              return null;
            },
          ),
        ],
      );
}
