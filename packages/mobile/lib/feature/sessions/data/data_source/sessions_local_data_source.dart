import 'dart:convert';

import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/replica/replica_keys.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_payload.dart';

abstract class SessionsLocalDataSource {
  Future<Replicated<BoardPayload>?> readBoard(String desktopId);
  Future<void> writeBoard(String desktopId, BoardPayload payload, DateTime fetchedAt);
  Future<void> deleteBoard(String desktopId);
}

class SessionsLocalDataSourceImp implements SessionsLocalDataSource {
  SessionsLocalDataSourceImp(this._dao);

  final ReplicaDocumentDao _dao;

  @override
  Future<Replicated<BoardPayload>?> readBoard(String desktopId) async {
    final rows = {for (final row in await _dao.read(desktopId, ReplicaKeys.board)) row.key: row};
    final sessions = rows[ReplicaKeys.boardSessions];
    if (sessions == null) return null;
    return Replicated(
      value: BoardPayload(
        sessions: jsonDecode(sessions.body) as Map<String, dynamic>,
        projects: _decode(rows[ReplicaKeys.boardProjects]),
        accounts: _decode(rows[ReplicaKeys.boardAccounts]),
      ),
      fetchedAt: sessions.fetchedAt,
    );
  }

  @override
  Future<void> writeBoard(String desktopId, BoardPayload payload, DateTime fetchedAt) => _dao.write(desktopId, {
    ReplicaKeys.boardSessions: jsonEncode(payload.sessions),
    if (payload.projects != null) ReplicaKeys.boardProjects: jsonEncode(payload.projects),
    if (payload.accounts != null) ReplicaKeys.boardAccounts: jsonEncode(payload.accounts),
  }, fetchedAt);

  @override
  Future<void> deleteBoard(String desktopId) => _dao.remove(desktopId, ReplicaKeys.board);

  static Map<String, dynamic>? _decode(ReplicaDocumentEntity? row) =>
      row == null ? null : jsonDecode(row.body) as Map<String, dynamic>;
}
