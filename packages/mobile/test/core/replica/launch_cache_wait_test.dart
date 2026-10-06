import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/replica/launch_cache_wait.dart';

void main() {
  test('returns as soon as the cache read completes, before the timeout elapses', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      var done = false;
      unawaited(waitForLaunchCache(completer.future, const Duration(milliseconds: 400)).then((_) => done = true));

      completer.complete();
      async.elapse(const Duration(milliseconds: 10));

      expect(done, isTrue);
    });
  });

  test('gives up once the timeout elapses when the cache read never completes', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      var done = false;
      unawaited(waitForLaunchCache(completer.future, const Duration(milliseconds: 400)).then((_) => done = true));

      async.elapse(const Duration(milliseconds: 399));
      expect(done, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
    });
  });

  test('never throws when the cache read fails', () {
    fakeAsync((async) {
      final completer = Completer<void>();
      var done = false;
      unawaited(waitForLaunchCache(completer.future, const Duration(milliseconds: 400)).then((_) => done = true));

      completer.completeError(StateError('cache read failed'));
      async.elapse(const Duration(milliseconds: 10));

      expect(done, isTrue);
    });
  });
}
