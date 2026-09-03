import 'dart:async';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

/// One CDC event stream for the whole app, fanned out per session.
///
/// This is the SSE counterpart to `MuxClient` and lives in `core/` for the same
/// reason: the chat chrome and the timeline both depend on it, so neither
/// feature can own it. It holds the cursor, the reconnection policy and the
/// liveness signal, and subscribers hold none of those.
///
/// The cursor is deliberately in-memory only. Every subscriber refetches its own
/// snapshot when it subscribes and again on [reconnects], so replaying history
/// across app launches buys nothing — and a cursor that is never durable can
/// never be stale, ahead of a reset log, or persisted before the refresh that
/// consumes it.
class ConversationEventBus {
  ConversationEventBus(
    this._source, {
    this._reconnectMin = const Duration(seconds: 1),
    this._reconnectMax = const Duration(seconds: 15),
  });

  final ChatEventDataSource _source;
  final Duration _reconnectMin;
  final Duration _reconnectMax;

  final _statusController = StreamController<EventStreamStatus>.broadcast();
  final _eventsController = StreamController<ConversationEventModel>.broadcast();
  final _reconnectsController = StreamController<void>.broadcast();

  Stream<EventStreamStatus> get status => _statusController.stream;
  Stream<void> get reconnects => _reconnectsController.stream;

  EventStreamStatus _currentStatus = EventStreamStatus.connecting;
  EventStreamStatus get currentStatus => _currentStatus;

  StreamSubscription<ConversationEventModel>? _sub;
  CancelToken? _cancel;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = Duration.zero;
  int? _cdcSeq;
  bool _wanted = false;

  Stream<ConversationEventModel> eventsFor(String sessionId) => _eventsController
      .stream
      .where(
        (event) => event.sessionId == sessionId && event.touchesConversation,
      );

  void connect() {
    if (_wanted && _sub != null) return;
    _wanted = true;
    _reconnectDelay = _reconnectMin;
    _open();
  }

  void onResumed() {
    if (!_wanted) return connect();
    _reconnectDelay = _reconnectMin;
    _open();
  }

  Future<void> disconnect() async {
    _wanted = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    _cancel?.cancel('bus disconnected');
    _cancel = null;
  }

  void _setStatus(EventStreamStatus next) {
    _currentStatus = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _open() {
    if (!_wanted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _cancel?.cancel('reopening');

    _setStatus(EventStreamStatus.connecting);
    final cancelToken = CancelToken();
    _cancel = cancelToken;
    _sub = _source
        .stream(after: _cursor(), cancelToken: cancelToken)
        .listen(
          _onEvent,
          onError: (Object _, StackTrace _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
    _setStatus(EventStreamStatus.connected);
    if (!_reconnectsController.isClosed) _reconnectsController.add(null);
  }

  CdcCursor _cursor() =>
      _cdcSeq == null ? const CdcCursor.latest() : CdcCursor.at(_cdcSeq!);

  void _onEvent(ConversationEventModel event) {
    _reconnectDelay = _reconnectMin;
    final seq = event.seq;
    if (_cdcSeq == null || seq > _cdcSeq!) _cdcSeq = seq;
    if (!_eventsController.isClosed) _eventsController.add(event);
  }

  void _scheduleReconnect() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (!_wanted) return;
    _setStatus(EventStreamStatus.reconnecting);
    if (_reconnectDelay == Duration.zero) _reconnectDelay = _reconnectMin;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _open);
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectMax ? _reconnectMax : next;
  }
}
