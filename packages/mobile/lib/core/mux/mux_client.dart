import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';

const int _ackEveryBytes = 5000;

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

final class BlockEventEnvelope extends Equatable {
  const BlockEventEnvelope(this.sessionId, this.block);

  final String sessionId;
  final Map<String, dynamic> block;

  @override
  List<Object?> get props => [sessionId, block];
}

/// One WebSocket multiplexing session-status snapshots and per-session
/// terminal I/O. Auto-reconnects with backoff. See `docs/mobile-parity-ledger.md`
/// for the RN reference (`lib/mux.ts`) this mirrors.
class MuxClient {
  MuxClient(this._configSource, {MuxSocket Function(Uri uri, Map<String, String> headers)? connect})
    : _connect = connect ?? IOMuxSocket.connect {
    _configSource.changes.listen(_onConfigChanged);
  }

  final ServerConfigSource _configSource;
  final MuxSocket Function(Uri uri, Map<String, String> headers) _connect;

  final _statusController = StreamController<MuxStatus>.broadcast();
  final _boardChangesController = StreamController<void>.broadcast();
  final _sessionPatchesController = StreamController<List<SessionPatch>>.broadcast();
  final _terminalEventsController = StreamController<TerminalEvent>.broadcast();
  final _blockEventsController = StreamController<BlockEventEnvelope>.broadcast();
  final _notificationsController = StreamController<MuxNotification>.broadcast();

  Stream<void> get boardChanges => _boardChangesController.stream;
  bool get boardStreamReady => _boardStreamReady;

  Stream<MuxStatus> get status => _statusController.stream;
  Stream<List<SessionPatch>> get sessionPatches => _sessionPatchesController.stream;
  Stream<TerminalEvent> get terminalEvents => _terminalEventsController.stream;
  Stream<BlockEventEnvelope> get blockEvents => _blockEventsController.stream;
  Stream<MuxNotification> get notifications => _notificationsController.stream;

  MuxSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  bool _isOpen = false;
  bool _boardStreamReady = false;
  bool _closedByUser = true;
  ServerConfig? _dialled;
  int _dialGeneration = 0;
  Timer? _reconnectTimer;
  ConnectionSignals? _connection;
  StreamSubscription<void>? _retrySub;
  bool _parked = false;
  Timer? _pingTimer;
  int _backoffMs = MuxBackoff.initialMs;
  final Map<String, String?> _openTerminals = {};
  final Map<String, int> _consumedBytes = {};
  final Map<String, int> _ackedBytes = {};
  final Set<String> _blockSessions = {};
  bool _subscribed = false;
  bool _notificationsSubscribed = false;

  MuxStatus _currentStatus = MuxStatus.closed;

  MuxStatus get currentStatus => _currentStatus;

  void _setStatus(MuxStatus status) {
    if (status != MuxStatus.open) _boardStreamReady = false;
    _currentStatus = status;
    _statusController.add(status);
  }

  void bindConnection(ConnectionSignals connection) {
    unawaited(_retrySub?.cancel());
    _connection = connection;
    _retrySub = connection.retries.listen((_) => _unpark());
  }

  bool get _authFailed => _connection?.authFailed ?? false;

  void _unpark() {
    if (!_parked || _closedByUser || _authFailed) return;
    _parked = false;
    _backoffMs = MuxBackoff.initialMs;
    unawaited(_open());
  }

  void connect() {
    if (_isOpen || _currentStatus == MuxStatus.connecting) return;
    _closedByUser = false;
    _reconnectTimer?.cancel();
    if (_authFailed) {
      _parked = true;
      return;
    }
    unawaited(_open());
  }

  Future<void> _open() async {
    _setStatus(MuxStatus.connecting);
    final cfg = _configSource.current;
    if (cfg == null) {
      _setStatus(MuxStatus.error);
      _scheduleReconnect();
      return;
    }
    final uri = Uri.parse('${cfg.wsBase}/mux');
    // No Origin header: this is a native client, not a browser. The daemon's
    // CORS allowlist 403s every Origin it does not know, which would reject the
    // upgrade before it reaches the mux handler.
    final headers = {
      if (cfg.password.isNotEmpty) 'Authorization': 'Bearer ${cfg.password}',
    };

    final socket = _connect(uri, headers);
    _socket = socket;
    _dialled = cfg;
    final generation = _dialGeneration;

    try {
      await socket.ready;
    } catch (_) {
      if (generation != _dialGeneration) return;
      _setStatus(MuxStatus.error);
      _scheduleReconnect();
      return;
    }

    if (_closedByUser || generation != _dialGeneration) {
      await socket.close();
      return;
    }

    _sub = socket.messages.listen(
      _onMessage,
      onError: (Object _) => _setStatus(MuxStatus.error),
      onDone: _onClosed,
    );

    _isOpen = true;
    _backoffMs = MuxBackoff.initialMs;
    _setStatus(MuxStatus.open);

    if (_subscribed) subscribeSessions();
    _consumedBytes.clear();
    _ackedBytes.clear();
    for (final entry in _openTerminals.entries) {
      _send({'ch': 'terminal', 'id': entry.key, 'type': 'open', 'projectId': entry.value, 'role': 'secondary'});
    }
    for (final sessionId in _blockSessions) {
      _send({'ch': 'blocks', 'id': sessionId, 'type': 'subscribe'});
    }
    if (_notificationsSubscribed) _send({'ch': 'notifications', 'type': 'subscribe'});

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

    if (ch == 'sessions' && type == 'subscribed') {
      _boardStreamReady = true;
      _boardChangesController.add(null);
      return;
    }

    if (ch == 'sessions' && type == 'snapshot') {
      final change = msg['session'];
      if (change is Map<String, dynamic>) {
        final eventType = change['eventType'];
        if (eventType is String &&
            (eventType.startsWith('session_') || eventType.startsWith('project_') || eventType.startsWith('pr_'))) {
          _boardChangesController.add(null);
        }
        final sessionId = change['sessionId'];
        if (eventType == 'session_updated' && sessionId is String) {
          final patch = SessionPatch.fromChangePayload(sessionId, change['payload']);
          if (patch != null) _sessionPatchesController.add([patch]);
        }
        return;
      }
      return;
    }

    if (ch == 'notifications' && type == 'notification') {
      final notification = MuxNotification.fromJson(msg['notification']);
      if (notification != null) _notificationsController.add(notification);
      return;
    }

    if (ch == 'terminal') {
      final id = msg['id'] as String? ?? '';
      switch (type) {
        case 'data':
          final bytes = base64Decode(msg['data'] as String? ?? '');
          _terminalEventsController.add(TerminalDataEvent(id, bytes));
          _noteConsumed(id, bytes.length);
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

    if (ch == 'blocks' && type == 'block') {
      final block = msg['block'];
      if (block is Map<String, dynamic>) {
        _blockEventsController.add(BlockEventEnvelope(msg['id'] as String? ?? '', block));
      }
    }
  }

  void _onConfigChanged(ServerConfig? next) {
    if (_closedByUser || (_dialled == next && !_parked)) return;
    _parked = false;
    _dialGeneration++;
    _reconnectTimer?.cancel();
    _clearPing();
    _isOpen = false;
    _dialled = null;
    unawaited(_sub?.cancel());
    unawaited(_socket?.close());
    _sub = null;
    _socket = null;
    if (next == null) {
      _setStatus(MuxStatus.closed);
      return;
    }
    unawaited(_open());
  }

  void _onClosed() {
    _isOpen = false;
    _clearPing();
    _setStatus(MuxStatus.closed);
    if (!_closedByUser) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    if (_authFailed) {
      _parked = true;
      return;
    }
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () {
      _reconnectTimer = null;
      if (_closedByUser) return;
      if (_authFailed) {
        _parked = true;
        return;
      }
      unawaited(_open());
    });
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
    _send({
      'ch': 'subscribe',
      'type': 'subscribe',
      'topics': ['sessions', 'notifications'],
    });
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

  void _noteConsumed(String id, int bytes) {
    if (id.isEmpty || bytes <= 0) return;
    final consumed = (_consumedBytes[id] ?? 0) + bytes;
    _consumedBytes[id] = consumed;
    if (consumed - (_ackedBytes[id] ?? 0) < _ackEveryBytes) return;
    _ackedBytes[id] = consumed;
    ackTerminal(id, consumed, projectId: _openTerminals[id]);
  }

  void ackTerminal(String id, int bytes, {String? projectId}) {
    _send({'ch': 'terminal', 'id': id, 'type': 'ack', 'bytes': bytes, 'projectId': projectId});
  }

  void closeTerminal(String id, {String? projectId}) {
    _openTerminals.remove(id);
    _consumedBytes.remove(id);
    _ackedBytes.remove(id);
    _send({'ch': 'terminal', 'id': id, 'type': 'close', 'projectId': projectId});
  }

  void subscribeBlocks(String sessionId) {
    _blockSessions.add(sessionId);
    _send({'ch': 'blocks', 'id': sessionId, 'type': 'subscribe'});
  }

  void unsubscribeBlocks(String sessionId) {
    _blockSessions.remove(sessionId);
    _send({'ch': 'blocks', 'id': sessionId, 'type': 'unsubscribe'});
  }

  void subscribeNotifications() {
    _notificationsSubscribed = true;
    _send({'ch': 'notifications', 'type': 'subscribe'});
  }

  void unsubscribeNotifications() {
    _notificationsSubscribed = false;
    _send({'ch': 'notifications', 'type': 'unsubscribe'});
  }

  Future<void> disconnect() async {
    _closedByUser = true;
    _parked = false;
    _reconnectTimer?.cancel();
    _clearPing();
    _isOpen = false;
    _dialled = null;
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    _setStatus(MuxStatus.closed);
  }
}
