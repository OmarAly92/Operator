import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

enum MuxStatus { connecting, open, closed, error }

sealed class TerminalEvent extends Equatable {
  const TerminalEvent(this.id);
  final String id;
}

final class TerminalDataEvent extends TerminalEvent {
  const TerminalDataEvent(super.id, this.bytes);
  final Uint8List bytes;
  @override
  List<Object?> get props => [id, bytes];
}

final class TerminalOpenedEvent extends TerminalEvent {
  const TerminalOpenedEvent(super.id);
  @override
  List<Object?> get props => [id];
}

final class TerminalExitedEvent extends TerminalEvent {
  const TerminalExitedEvent(super.id, this.code);
  final int code;
  @override
  List<Object?> get props => [id, code];
}

final class TerminalErrorEvent extends TerminalEvent {
  const TerminalErrorEvent(super.id, this.message);
  final String message;
  @override
  List<Object?> get props => [id, message];
}

final class TerminalResizeEvent extends TerminalEvent {
  const TerminalResizeEvent(super.id, this.cols, this.rows);
  final int cols;
  final int rows;
  @override
  List<Object?> get props => [id, cols, rows];
}

/// One WebSocket multiplexing session-status snapshots and per-session
/// terminal I/O. Auto-reconnects with backoff. See `lib/mux.ts` in
/// `packages/mobile_rn` for the RN reference this mirrors.
class MuxClient {
  MuxClient(this._cfg, {MuxSocket Function(Uri uri, Map<String, String> headers)? connect})
    : _connect = connect ?? IOMuxSocket.connect;

  final ServerConfig _cfg;
  final MuxSocket Function(Uri uri, Map<String, String> headers) _connect;

  final _statusController = StreamController<MuxStatus>.broadcast();
  final _sessionPatchesController = StreamController<List<SessionPatch>>.broadcast();
  final _terminalEventsController = StreamController<TerminalEvent>.broadcast();

  Stream<MuxStatus> get status => _statusController.stream;
  Stream<List<SessionPatch>> get sessionPatches => _sessionPatchesController.stream;
  Stream<TerminalEvent> get terminalEvents => _terminalEventsController.stream;

  MuxSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  bool _isOpen = false;
  bool _closedByUser = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _backoffMs = MuxBackoff.initialMs;
  final Map<String, String?> _openTerminals = {};
  bool _subscribed = false;

  void connect() {
    _closedByUser = false;
    unawaited(_open());
  }

  Future<void> _open() async {
    _statusController.add(MuxStatus.connecting);
    final uri = Uri.parse('${_cfg.wsBase}/mux');
    final headers = {
      'Origin': 'http://localhost',
      if (_cfg.password.isNotEmpty) 'Authorization': 'Bearer ${_cfg.password}',
    };

    final socket = _connect(uri, headers);
    _socket = socket;

    try {
      await socket.ready;
    } catch (_) {
      _statusController.add(MuxStatus.error);
      _scheduleReconnect();
      return;
    }

    _sub = socket.messages.listen(
      _onMessage,
      onError: (Object _) => _statusController.add(MuxStatus.error),
      onDone: _onClosed,
    );

    _isOpen = true;
    _backoffMs = MuxBackoff.initialMs;
    _statusController.add(MuxStatus.open);

    if (_subscribed) _send({'ch': 'subscribe', 'topics': ['sessions', 'notifications']});
    for (final entry in _openTerminals.entries) {
      _send({'ch': 'terminal', 'id': entry.key, 'type': 'open', 'projectId': entry.value, 'role': 'secondary'});
    }

    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => _send({'ch': 'system', 'type': 'ping'}));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final ch = msg['ch'] as String?;
    final type = msg['type'] as String?;

    if (ch == 'sessions' && type == 'snapshot') {
      final rawSessions = msg['sessions'] as List<dynamic>? ?? [];
      _sessionPatchesController.add(
        rawSessions.map((s) => SessionPatch.fromJson(s as Map<String, dynamic>)).toList(),
      );
      return;
    }

    if (ch == 'terminal') {
      final id = msg['id'] as String? ?? '';
      switch (type) {
        case 'data':
          _terminalEventsController.add(TerminalDataEvent(id, base64Decode(msg['data'] as String? ?? '')));
        case 'opened':
          _terminalEventsController.add(TerminalOpenedEvent(id));
        case 'exited':
          _terminalEventsController.add(TerminalExitedEvent(id, (msg['code'] as num?)?.toInt() ?? 0));
        case 'error':
          _terminalEventsController.add(
            TerminalErrorEvent(id, (msg['error'] ?? msg['message'] ?? 'terminal error') as String),
          );
        case 'resize':
          final cols = msg['cols'];
          final rows = msg['rows'];
          if (cols is num && rows is num && cols > 0 && rows > 0) {
            _terminalEventsController.add(TerminalResizeEvent(id, cols.toInt(), rows.toInt()));
          }
      }
    }
  }

  void _onClosed() {
    _isOpen = false;
    _clearPing();
    _statusController.add(MuxStatus.closed);
    if (!_closedByUser) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () => unawaited(_open()));
    _backoffMs = MuxBackoff.next(_backoffMs);
  }

  void _clearPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _send(Map<String, dynamic> obj) {
    if (_isOpen) _socket?.send(jsonEncode(obj));
  }

  void subscribeSessions() {
    _subscribed = true;
    _send({'ch': 'subscribe', 'topics': ['sessions', 'notifications']});
  }

  void openTerminal(String id, {String? projectId}) {
    _openTerminals[id] = projectId;
    _send({'ch': 'terminal', 'id': id, 'type': 'open', 'projectId': projectId, 'role': 'secondary'});
  }

  void sendInput(String id, String data, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'data', 'data': base64Encode(utf8.encode(data)), 'projectId': projectId});
  }

  void resize(String id, int cols, int rows, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'resize', 'cols': cols, 'rows': rows, 'projectId': projectId});
  }

  void closeTerminal(String id, {String? projectId}) {
    _openTerminals.remove(id);
    _send({'ch': 'terminal', 'id': id, 'type': 'close', 'projectId': projectId});
  }

  Future<void> disconnect() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _clearPing();
    _isOpen = false;
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
  }
}
