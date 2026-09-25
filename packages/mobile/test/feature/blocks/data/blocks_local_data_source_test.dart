import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BlocksLocalDataSourceImp source;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = BlocksLocalDataSourceImp(db.replicaBlockEventDao);
  });

  tearDown(() => db.close());

  test('writeHistory then readHistory returns the rows oldest first, keyed by seq', () async {
    await source.writeHistory('a', 's-1', [
      {'seq': 2, 'kind': 'stop'},
      {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
    ]);

    expect(await source.readHistory('a', 's-1'), [
      {'seq': 1, 'kind': 'prompt_submit', 'text': 'hi'},
      {'seq': 2, 'kind': 'stop'},
    ]);
  });

  test('keeps only the newest events per session', () async {
    await source.writeHistory('a', 's-1', [for (var seq = 1; seq <= 230; seq++) {'seq': seq}]);

    final rows = await source.readHistory('a', 's-1');

    expect(rows, hasLength(ReplicaLimits.blockEventsPerSession));
    expect(rows.first['seq'], 31);
  });

  test('deleteHistory removes that session', () async {
    await source.writeHistory('a', 's-1', [{'seq': 1}]);

    await source.deleteHistory('a', 's-1');

    expect(await source.readHistory('a', 's-1'), isEmpty);
  });
}
