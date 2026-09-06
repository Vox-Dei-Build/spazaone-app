import 'package:flutter/material.dart';

class LogoDisplay extends StatelessWidget {
  const LogoDisplay({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/images/spazaone_logo_horizontal.png',
          width: 136,
          height: 36,
          fit: BoxFit.contain,
          semanticLabel: 'Spaza One',
        ),
      );
}
