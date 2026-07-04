import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/main.dart';
import 'package:pasella/pages/auth/login/login.dart';

void main() {
  test('unknown route fallback returns a real route', () {
    final route = MyApp.buildUnknownRoute(
      const RouteSettings(name: '/stale-or-unknown-route'),
    );

    expect(route, isA<Route<dynamic>>());
    expect(route.settings.name, LoginPage.id);
  });
}
