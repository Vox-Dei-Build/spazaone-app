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

  test('commerce notifications open the customer Orders tab', () {
    expect(
      customerNotificationTabIndex(
        const {'notificationType': 'commerce_order'},
      ),
      1,
    );
    expect(
      customerNotificationTabIndex(
        const {'action': 'open_customer_messages'},
      ),
      2,
    );
  });

  test('verification notifications deep-link to Online payments', () {
    expect(
      isOnlinePaymentsNotificationRoute(
        Uri.parse('/walletPage?destination=online_payments'),
      ),
      isTrue,
    );
    expect(
      isOnlinePaymentsNotificationRoute(Uri.parse('/walletPage')),
      isFalse,
    );
  });

  test('operations alerts open only the authenticated workspace origin', () {
    const data = {'notificationType': 'payment_operations'};
    expect(
      isPaymentOperationsWorkspaceNotification(
        Uri.parse('https://workspace.spazaone.com/'),
        data,
      ),
      isTrue,
    );
    expect(
      isPaymentOperationsWorkspaceNotification(
        Uri.parse('https://workspace.spazaone.example/'),
        data,
      ),
      isFalse,
    );
    expect(
      isPaymentOperationsWorkspaceNotification(
        Uri.parse('http://workspace.spazaone.com/'),
        data,
      ),
      isFalse,
    );
  });
}
