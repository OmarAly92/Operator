import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-party code keeps no key-value store beside drift', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('package:shared_preferences/') || source.contains('cache_helper.dart')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'drift is the only local store: settings go through AppPreferences, and the Keychain holds '
          'passwords only. Offenders: $offenders',
    );
  });
}
