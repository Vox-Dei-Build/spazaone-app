import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/design/spaza_theme.dart';

void main() {
  testWidgets('plain theme controls use the bundled font across platforms',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildSpazaTheme().copyWith(platform: platform),
        home: Scaffold(
            body: Column(children: [
          FilledButton(onPressed: () {}, child: const Text('Save')),
          OutlinedButton(onPressed: () {}, child: const Text('Details')),
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          ElevatedButton(onPressed: () {}, child: const Text('Continue')),
        ])),
      ));
      for (final label in ['Save', 'Details', 'Cancel', 'Continue']) {
        final context = tester.element(find.text(label));
        expect(DefaultTextStyle.of(context).style.fontFamily, 'SpazaSans');
        expect(DefaultTextStyle.of(context).style.fontSize, 14);
      }
    }
  });

  testWidgets(
      'legacy typography stays stable through rotation and larger screens',
      (tester) async {
    for (final size in [
      const Size(360, 640),
      const Size(640, 360),
      const Size(1024, 1366)
    ]) {
      await tester.pumpWidget(MediaQuery(
        data:
            MediaQueryData(size: size, textScaler: const TextScaler.linear(2)),
        child: Builder(builder: (context) {
          SizeConfig().init(context);
          expect(SizeConfig.textMultiplier, 8);
          expect(MediaQuery.textScalerOf(context).scale(14), 28);
          return const SizedBox.shrink();
        }),
      ));
    }
  });
}
