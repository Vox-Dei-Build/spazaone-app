import 'package:flutter/material.dart';

class IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final Color color;
  final bool disabled;

  const IconActionButton({
    Key? key,
    required this.icon,
    required this.onTap,
    required this.label,
    this.disabled = false,
    this.color = Colors.black,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // Use min to fit content
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          iconSize: 30,
          onPressed: disabled ? null : onTap,
          padding: EdgeInsets.zero, // Keep padding minimal
          constraints: BoxConstraints(
            minWidth: 60.0, // Consistent sizing for tap targets
            minHeight: 60.0,
          ),
        ),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold)), // Add text label below icon
      ],
    );
  }
}
