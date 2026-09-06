import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';

void main() {
  test('concurrent promotion loads for one store share their reads', () async {
    final coalescer = PromotionsInitialLoadCoalescer();
    final completion = Completer<void>();
    var calls = 0;

    Future<void> load() {
      calls++;
      return completion.future;
    }

    final first = coalescer.run('store-a', load);
    final second = coalescer.run('store-a', load);

    expect(calls, 1);
    expect(identical(first, second), isTrue);

    completion.complete();
    await Future.wait([first, second]);
  });

  test('completed and cross-store loads remain fresh and isolated', () async {
    final coalescer = PromotionsInitialLoadCoalescer();
    var calls = 0;

    Future<void> load() async {
      calls++;
    }

    await coalescer.run('store-a', load);
    await coalescer.run('store-a', load);
    await coalescer.run('store-b', load);

    expect(calls, 3);
  });
}
