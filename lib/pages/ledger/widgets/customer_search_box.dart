import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          height: 48,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search,
                size: 20,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search customers',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    // PAS-UX: the clear button only renders once the
                    // merchant has typed something. Previously it sat
                    // there permanently, adding visual noise and
                    // suggesting an action was always available.
                    suffixIcon: hasText
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () {
                              _controller.clear();
                            },
                          )
                        : null,
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
