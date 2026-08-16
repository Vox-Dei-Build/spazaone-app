import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/workspace_search_field.dart';

class CustomerSearchBox extends StatefulWidget {
  final ValueNotifier<String?> searchTextNotifier;

  /// Optional focus node owned by the parent. Used by `CustomerTab` so
  /// the sticky-on-scroll logic can keep the bar visible while the
  /// merchant is typing (otherwise scrolling within the keyboard's
  /// presence could collapse the field mid-input).
  final FocusNode? focusNode;

  const CustomerSearchBox({
    required this.searchTextNotifier,
    this.focusNode,
    Key? key,
  }) : super(key: key);

  @override
  _CustomerSearchBoxState createState() => _CustomerSearchBoxState();
}

class _CustomerSearchBoxState extends State<CustomerSearchBox> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChange);
  }

  void _handleTextChange() {
    widget.searchTextNotifier.value = _controller.text;
    // PAS-UX: rebuild so the clear (×) suffix only paints when the
    // input has content. Cheap — the widget is a tiny leaf.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: WorkspaceSearchField(
        controller: _controller,
        focusNode: widget.focusNode,
        hintText: 'Search customers',
        semanticLabel: 'Search customers by name',
      ),
    );
  }
}
