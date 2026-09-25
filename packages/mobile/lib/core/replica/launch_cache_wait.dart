import 'dart:async';

Future<void> waitForLaunchCache(Future<void> cacheRead, Duration timeout) =>
    cacheRead.timeout(timeout, onTimeout: () {}).catchError((_) {});
