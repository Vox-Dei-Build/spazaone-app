import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// One quiet, predictable search treatment for Customers, Products and the
/// supplier catalogue. Search is a workspace tool, not a primary action, so
/// the field uses a neutral surface and reserves brand green for CTAs.
class WorkspaceSearchField extends StatefulWidget {
  const WorkspaceSearchField({
    super.key,
    required this.hintText,
    required this.semanticLabel,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.searchActionLabel,
  });

  final String hintText;
  final String semanticLabel;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool enabled;
  final bool autofocus;
  final String? searchActionLabel;

  @override
  State<WorkspaceSearchField> createState() => _WorkspaceSearchFieldState();
}

class _WorkspaceSearchFieldState extends State<WorkspaceSearchField> {
  TextEditingController? _ownedController;
  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant WorkspaceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(_rebuild);
      _ownedController?.dispose();
      _ownedController = null;
      _controller.addListener(_rebuild);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;
    return Semantics(
      container: true,
      textField: !widget.readOnly,
      button: widget.readOnly,
      label: widget.semanticLabel,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium,
        onTap: widget.onTap,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(SpazaIcons.search, size: 20),
          suffixIcon: hasText && !widget.readOnly
              ? IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 20),
                )
              : widget.searchActionLabel != null
                  ? IconButton(
                      tooltip: widget.searchActionLabel,
                      onPressed: widget.enabled
                          ? () => widget.onSubmitted?.call(_controller.text)
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    )
                  : widget.readOnly
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
          filled: true,
          fillColor: colors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            borderSide:
                const BorderSide(color: SpazaColors.heading, width: 1.5),
          ),
        ),
      ),
    );
  }
}
