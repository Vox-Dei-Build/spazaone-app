import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

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
    final hasText = _controller.text.isNotEmpty;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Search customers by name',
      child: Padding(
        // PAS-UX: align with EntityTab's horizontal list padding so the
        // search field reads as anchored to the list it filters rather
        // than as a floating banner above it.
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 2,
        ),
        child: TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          decoration: InputDecoration(
            hintText: 'Search customers',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .42),
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
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: hasText
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _controller.clear,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
