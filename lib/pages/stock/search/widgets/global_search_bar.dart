import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

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
    SizeConfig().init(context); // Initialize SizeConfig

    return Padding(
      padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 5),
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        onFieldSubmitted: widget.onSearch,
        textInputAction: TextInputAction.search,
        key: UniqueKey(),
        keyboardType: TextInputType.text,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2,
        ),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(SizeConfig.imageSizeMultiplier * 2),
            borderSide: BorderSide(
              color: Colors.grey.withOpacity(0.6),
            ),
          ),
          hintText: "Product Name (Press Enter)",
          filled: true,
          fillColor: Colors.transparent,
          hintStyle: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2,
            color: Colors.grey.withOpacity(0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.grey,
            size: SizeConfig.imageSizeMultiplier * 6,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.clear,
              size: SizeConfig.imageSizeMultiplier * 6,
            ),
            onPressed: () {
              _controller.clear();
            },
          ),
        ),
        cursorColor: Colors.grey,
      ),
    );
  }
}
