import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';

void main() {
  late AppDatabase db;
  late NotificationLocalDataSourceImp source;
  final at = DateTime.utc(2026, 9, 25, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    source = NotificationLocalDataSourceImp(db.replicaDocumentDao);
  });

  tearDown(() => db.close());

  test('writeFirstPage then readFirstPage round-trips the body per desktop', () async {
    await source.writeFirstPage('a', {'notifications': [], 'unreadCount': 3}, at);

    final stored = await source.readFirstPage('a');

    expect(stored!.value, {'notifications': [], 'unreadCount': 3});
    expect(stored.fetchedAt.isAtSameMomentAs(at), isTrue);
    expect(await source.readFirstPage('b'), isNull);
  });

  test('deleteFirstPage removes it', () async {
    await source.writeFirstPage('a', {'notifications': []}, at);

    await source.deleteFirstPage('a');

    expect(await source.readFirstPage('a'), isNull);
  });
}
