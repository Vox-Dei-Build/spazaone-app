import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/services/crash_service.dart';

class OrdersRepository {
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  /// Default call timeout. The Functions SDK has its own 60s default, but
  /// we want to fail faster and retry once on transient infra errors so
  /// the spinner doesn't spin forever on flaky networks.
  static const Duration _callTimeout = Duration(seconds: 25);

  const OrdersRepository({required this.auth, required this.functions});

  Future<List<OrderModel>> fetchCustomerOrders({
    required String merchantId,
    required String customerId,
  }) async {
    final result = await _callWithRetry(
      name: 'getCustomerOrders',
      payload: {
        'merchantId': merchantId,
        'customerId': customerId,
      },
    );

    final List<dynamic> data = result.data['orders'] ?? [];
    return data
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Calls a callable function with one retry on transient errors.
  ///
  /// Background: Crashlytics has repeatedly captured a fatal
  ///   `[firebase_functions/unknown] java.util.concurrent.ExecutionException:
  ///    1 out of 2 underlying tasks failed`
  /// from this code path. The Android Functions SDK awaits a pair of
  /// `Tasks` (auth token + context/AppCheck) via `Tasks.whenAll` before
  /// firing the HTTP request; if either fails (most often a transient
  /// auth-token refresh on a flaky connection), the whole call surfaces
  /// as `unknown`. A single short-backoff retry recovers the vast
  /// majority of these without the user ever seeing the error state,
  /// and we demote what remains to a non-fatal so the orders page can
  /// render its existing "Couldn't load orders" UI instead of crashing
  /// the FutureBuilder.
  Future<HttpsCallableResult<dynamic>> _callWithRetry({
    required String name,
    required Map<String, dynamic> payload,
  }) async {
    final callable = functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: _callTimeout),
    );

    try {
      return await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      if (!_isTransient(e)) rethrow;
      await CrashService.instance.log(
        'callable transient failure, retrying',
        context: {'fn': name, 'code': e.code},
      );
      // Short backoff to give the auth/AppCheck token a chance to refresh.
      await Future.delayed(const Duration(milliseconds: 600));
      try {
        return await callable.call(payload);
      } on FirebaseFunctionsException catch (e2, st2) {
        // Final failure: record as non-fatal (not a crash) and rethrow so
        // the caller's FutureBuilder shows the error state.
        await CrashService.instance.recordNonFatal(
          e2,
          st2,
          reason: 'callable $name failed after retry',
          context: {'fn': name, 'code': e2.code},
        );
        rethrow;
      }
    } on TimeoutException catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'callable $name timed out',
        context: {'fn': name},
      );
      rethrow;
    } on SocketException catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'callable $name network error',
        context: {'fn': name},
      );
      rethrow;
    }
  }

  /// Codes we consider safe to retry once. These are infra / transport
  /// failures, not business-logic rejections from the function body.
  bool _isTransient(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unknown':
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
      case 'aborted':
      case 'cancelled':
        return true;
      default:
        return false;
    }
  }
}
