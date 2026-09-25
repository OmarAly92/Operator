import 'dart:convert';

import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/replica/replica_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';

abstract class NotificationLocalDataSource {
  Future<Replicated<Map<String, dynamic>>?> readFirstPage(String desktopId);
  Future<void> writeFirstPage(String desktopId, Map<String, dynamic> body, DateTime fetchedAt);
  Future<void> deleteFirstPage(String desktopId);
}

class NotificationLocalDataSourceImp implements NotificationLocalDataSource {
  NotificationLocalDataSourceImp(this._dao);

  final ReplicaDocumentDao _dao;

  @override
  Future<Replicated<Map<String, dynamic>>?> readFirstPage(String desktopId) async {
    final rows = await _dao.read(desktopId, const [ReplicaKeys.notificationsFirst]);
    if (rows.isEmpty) return null;
    return Replicated(value: jsonDecode(rows.single.body) as Map<String, dynamic>, fetchedAt: rows.single.fetchedAt);
  }

  @override
  Future<void> writeFirstPage(String desktopId, Map<String, dynamic> body, DateTime fetchedAt) =>
      _dao.write(desktopId, {ReplicaKeys.notificationsFirst: jsonEncode(body)}, fetchedAt);

  @override
  Future<void> deleteFirstPage(String desktopId) => _dao.remove(desktopId, const [ReplicaKeys.notificationsFirst]);
}
