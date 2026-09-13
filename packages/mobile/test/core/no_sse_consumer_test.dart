import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app consumes no SSE, which the cloudflared fallback depends on', () {
    final offenders = <String>[];
    final pattern = RegExp(r"text/event-stream|EventSource|ResponseType\.stream");

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (pattern.hasMatch(source)) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'cloudflared quick tunnels buffer SSE, so an SSE consumer would make live '
          'updates arrive in batches with no error on that path. Either keep live data '
          'on the mux WebSocket, or drop the cloudflared fallback. Offenders: $offenders',
    );
  });
}
