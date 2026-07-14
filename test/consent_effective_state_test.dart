import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/consent_service.dart';

void main() {
  group('ConsentState effective gates', () {
    test('first-run defaults are presentation-only until decided', () {
      const state = ConsentState.firstRun();

      expect(state.analytics, isTrue);
      expect(state.crash, isTrue);
      expect(state.replay, isFalse);
      expect(state.hasDecided, isFalse);
      expect(state.effectiveAnalytics, isFalse);
      expect(state.effectiveCrash, isFalse);
      expect(state.effectiveReplay, isFalse);
    });

    test('saved analytics and crash choices become effective after decision', () {
      final decided = ConsentState(
        analytics: true,
        replay: true,
        crash: true,
        decidedAt: DateTime(2026, 6, 22),
      );

      expect(decided.hasDecided, isTrue);
      expect(decided.effectiveAnalytics, isTrue);
      expect(decided.effectiveCrash, isTrue);
      expect(decided.effectiveReplay, isFalse);
    });

    test('replay remains disabled even for a legacy saved opt-in', () {
      final decided = ConsentState(
        analytics: false,
        replay: true,
        crash: true,
        decidedAt: DateTime(2026, 6, 22),
      );

      expect(decided.effectiveAnalytics, isFalse);
      expect(decided.effectiveReplay, isFalse);
      expect(decided.effectiveCrash, isTrue);
    });
  });
}
