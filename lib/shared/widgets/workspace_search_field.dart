import 'package:flutter/material.dart';

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
        onTap: widget.onTap,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
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
          fillColor: colors.surfaceContainerHighest.withValues(alpha: .58),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF30345F), width: 1.5),
          ),
        ),
      ),
    );
  }
}
