import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_backoff.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';

part 'connection_state.dart';

class ConnectionCubit extends Cubit<AppConnectionState> implements ConnectionSignals {
  ConnectionCubit(
    this._reports,
    Stream<MuxStatus> muxStatus,
    this._config, {
    Stream<String?>? desktopNames,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ConnectionConnectingState()) {
    _reportSub = _reports.stream.listen(_onReport);
    _muxSub = muxStatus.listen(_onMux);
    _configSub = _config.changes.listen(_onConfig);
    _nameSub = desktopNames?.listen(_onName, onError: (Object _) {});
    final last = _reports.last;
    if (last != null) _onReport(last);
  }

  final ConnectionReports _reports;
  final ServerConfigSource _config;
  final DateTime Function() _clock;
  final StreamController<void> _retries = StreamController<void>.broadcast();

  StreamSubscription<ConnectionReport>? _reportSub;
  StreamSubscription<MuxStatus>? _muxSub;
  StreamSubscription<ServerConfig?>? _configSub;
  StreamSubscription<String?>? _nameSub;
  Timer? _retryTimer;
  Duration _delay = ConnectionBackoff.initial;
  DateTime? _lastSeenAt;
  int _episode = 0;

  ServerConfig? get config => _config.current;

  @override
  Stream<void> get retries => _retries.stream;

  @override
  bool get authFailed => state is ConnectionAuthFailedState;

  void resumed() {
    if (isClosed || state is! ConnectionOfflineState) return;
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _retries.add(null);
  }

  void _onReport(ConnectionReport report) {
    if (isClosed) return;
    switch (report.outcome) {
      case ConnectionOutcome.online:
        if (authFailed && report.path == EndPoints.health) return;
        _goOnline(report.at);
      case ConnectionOutcome.auth:
        _goAuthFailed();
      case ConnectionOutcome.unreachable:
        _goOffline(ConnectionFailure.unreachable);
      case ConnectionOutcome.rateLimited:
        _goOffline(ConnectionFailure.rateLimited);
      case ConnectionOutcome.serverError:
        _goOffline(ConnectionFailure.serverError);
    }
  }

  void _onMux(MuxStatus status) {
    if (isClosed || _config.current == null) return;
    if (status == MuxStatus.open) {
      _goOnline(_clock());
    } else if (status == MuxStatus.error && state is ConnectionOnlineState) {
      _retries.add(null);
    }
  }

  void _onConfig(ServerConfig? next) {
    if (isClosed) return;
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _lastSeenAt = null;
    emit(ConnectionConnectingState(desktopName: state.desktopName));
  }

  void _onName(String? name) {
    if (isClosed || name == state.desktopName) return;
    emit(state.withName(name));
  }

  void _goOnline(DateTime at) {
    _cancelRetry();
    _delay = ConnectionBackoff.initial;
    _lastSeenAt = at;
    emit(ConnectionOnlineState(updatedAt: at, desktopName: state.desktopName));
  }

  void _goOffline(ConnectionFailure reason) {
    if (authFailed) return;
    emit(ConnectionOfflineState(reason: reason, lastSeenAt: _lastSeenAt, desktopName: state.desktopName));
    _scheduleRetry(reason);
  }

  void _goAuthFailed() {
    _cancelRetry();
    if (authFailed) return;
    _episode++;
    emit(ConnectionAuthFailedState(episode: _episode, desktopName: state.desktopName));
  }

  void _scheduleRetry(ConnectionFailure reason) {
    if (_retryTimer != null) return;
    final Duration wait;
    if (reason == ConnectionFailure.rateLimited) {
      wait = ConnectionBackoff.rateLimited;
    } else {
      wait = _delay;
      _delay = ConnectionBackoff.next(_delay);
    }
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      if (!isClosed && state is ConnectionOfflineState) _retries.add(null);
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> close() async {
    _cancelRetry();
    await _reportSub?.cancel();
    await _muxSub?.cancel();
    await _configSub?.cancel();
    await _nameSub?.cancel();
    await _retries.close();
    return super.close();
  }
}
