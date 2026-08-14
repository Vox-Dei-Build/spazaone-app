import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/workspace_search_field.dart';

class GlobalSearchBar extends StatefulWidget {
  final Function(String) onSearch;

  const GlobalSearchBar({Key? key, required this.onSearch}) : super(key: key);

  @override
  _GlobalSearchBarState createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // Call onSearch whenever the text changes
      widget.onSearch(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: WorkspaceSearchField(
        controller: _controller,
        autofocus: true,
        hintText: 'Search products',
        semanticLabel: 'Search products by name',
        onSubmitted: widget.onSearch,
      ),
    );
  }
}
