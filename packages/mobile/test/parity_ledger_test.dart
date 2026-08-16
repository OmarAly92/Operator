import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _ledgerPath = '../../docs/mobile-parity-ledger.md';
const String _rnRoot = '../mobile_rn';

final RegExp _sourceRow = RegExp(r'^\|\s*`([^`]+)`\s*\|\s*(?:`([^`]+)`|OMITTED)\s*\|');

List<String> _rnSourceFiles() {
  final root = Directory(_rnRoot);
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceFirst('$_rnRoot/', ''))
      .where((path) => path.startsWith('lib/') || path.startsWith('app/'))
      .where((path) => path.endsWith('.ts') || path.endsWith('.tsx'))
      .where((path) => !path.endsWith('.test.ts') && !path.endsWith('.test.tsx'))
      .toList()
    ..sort();
}

Map<String, String?> _ledgerRows() {
  final rows = <String, String?>{};
  for (final line in File(_ledgerPath).readAsLinesSync()) {
    final match = _sourceRow.firstMatch(line.trim());
    if (match == null) continue;
    final source = match.group(1)!;
    expect(rows.containsKey(source), isFalse, reason: '$source has more than one ledger row');
    rows[source] = match.group(2);
  }
  return rows;
}

void main() {
  group('parity ledger', () {
    test('has exactly one row per RN source file', () {
      final rows = _ledgerRows();
      final missing = _rnSourceFiles().where((path) => !rows.containsKey(path)).toList();
      expect(missing, isEmpty, reason: 'RN files with no ledger row:\n${missing.join('\n')}');
    });

    test('cites no RN file that does not exist', () {
      final sources = _rnSourceFiles().toSet();
      final stale = _ledgerRows().keys.where((path) => !sources.contains(path)).toList();
      expect(stale, isEmpty, reason: 'ledger rows for files that are gone:\n${stale.join('\n')}');
    });

    test('every cited Dart destination exists', () {
      final broken = <String>[];
      _ledgerRows().forEach((source, destination) {
        if (destination == null) return;
        if (!File(destination).existsSync() && !Directory(destination).existsSync()) {
          broken.add('$source -> $destination');
        }
      });
      expect(broken, isEmpty, reason: 'destinations that do not exist:\n${broken.join('\n')}');
    });
  });
}
