import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class LedgerFloatingActionButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LedgerFloatingActionButton({Key? key, required this.onPressed})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SizeConfig.heightMultiplier * 7,
      child: FloatingActionButton.extended(
        elevation: 3.0,
        onPressed: onPressed,
        icon: Icon(
          Icons.add_outlined,
          color: Colors.white,
          size: SizeConfig.heightMultiplier * 2.5,
        ),
        label: Text(
          'Add Customer',
          style: TextStyle(
            color: Colors.white,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
      ),
    );
  }
}
