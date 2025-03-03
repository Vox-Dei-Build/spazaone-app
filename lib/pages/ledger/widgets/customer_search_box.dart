import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

class CustomerSearchBox extends StatefulWidget {
  final ValueNotifier<String?> searchTextNotifier;
  const CustomerSearchBox({required this.searchTextNotifier, Key? key})
      : super(key: key);

  @override
  _CustomerSearchBoxState createState() => _CustomerSearchBoxState();
}

class _CustomerSearchBoxState extends State<CustomerSearchBox> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      widget.searchTextNotifier.value = _controller.text;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SizeConfig.heightMultiplier * 6,
      width: double.infinity,
      decoration: BoxDecoration(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Row(
        children: [
          SizedBox(width: SizeConfig.imageSizeMultiplier * 7),
          Icon(
            Icons.search,
            size: SizeConfig.imageSizeMultiplier * 5,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 7),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
              ),
              decoration: InputDecoration(
                hintText: 'Search...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: SizeConfig.imageSizeMultiplier * 5,
                  ),
                  onPressed: () {
                    _controller.clear();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
