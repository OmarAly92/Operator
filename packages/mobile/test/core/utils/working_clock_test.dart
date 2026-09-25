import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/working_clock.dart';

void main() {
  test('ticks only while someone listens and reads the time when it starts', () {
    fakeAsync((async) {
      var now = DateTime(2026, 9, 25, 12);
      final clock = WorkingClock(now: () => now);
      now = now.add(const Duration(seconds: 5));
      expect(clock.ticking, isFalse);

      void listener() {}
      clock.addListener(listener);
      expect(clock.ticking, isTrue);
      expect(clock.value, DateTime(2026, 9, 25, 12, 0, 5));

      clock.removeListener(listener);
      expect(clock.ticking, isFalse);
      clock.dispose();
    });
  });

  test('every listener sees the same value on the same tick', () {
    fakeAsync((async) {
      var now = DateTime(2026, 9, 25, 12);
      final clock = WorkingClock(now: () => now);
      final seen = <String, List<DateTime>>{'a': [], 'b': []};
      void a() => seen['a']!.add(clock.value);
      void b() => seen['b']!.add(clock.value);
      clock.addListener(a);
      async.elapse(const Duration(milliseconds: 400));
      clock.addListener(b);

      for (var tick = 0; tick < 3; tick++) {
        now = now.add(const Duration(milliseconds: 700));
        async.elapse(const Duration(milliseconds: 1000));
      }

      expect(seen['a'], hasLength(3));
      expect(seen['b'], seen['a']);
      clock.removeListener(a);
      clock.removeListener(b);
      clock.dispose();
    });
  });
}
