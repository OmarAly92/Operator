import 'dart:convert';

import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';

abstract class BlocksLocalDataSource {
  Future<List<Map<String, dynamic>>> readHistory(String desktopId, String sessionId);
  Future<void> writeHistory(String desktopId, String sessionId, List<Map<String, dynamic>> rows);
  Future<void> deleteHistory(String desktopId, String sessionId);
}

class BlocksLocalDataSourceImp implements BlocksLocalDataSource {
  BlocksLocalDataSourceImp(this._dao);

  final ReplicaBlockEventDao _dao;

  @override
  Future<List<Map<String, dynamic>>> readHistory(String desktopId, String sessionId) async => [
    for (final row in await _dao.latest(desktopId, sessionId)) jsonDecode(row.body) as Map<String, dynamic>,
  ];

  @override
  Future<void> writeHistory(String desktopId, String sessionId, List<Map<String, dynamic>> rows) =>
      _dao.write(desktopId, sessionId, {for (final row in rows) (row['seq'] as num).toInt(): jsonEncode(row)});

  @override
  Future<void> deleteHistory(String desktopId, String sessionId) => _dao.removeSession(desktopId, sessionId);
}
