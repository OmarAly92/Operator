import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/events/sse_stream.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';

part 'preview_state.dart';

class PreviewCubit extends Cubit<PreviewState> with WidgetsBindingObserver {
  PreviewCubit(
    this._repository,
    this.sessionId, {
    this.previewUrl,
    Duration poll = const Duration(seconds: 30),
    Stream<SseStreamEvent> Function()? workspaceEvents,
    Stream<SessionModel> Function()? sessionUpdates,
  }) : _poll = poll,
       _workspaceEvents = workspaceEvents,
       _sessionUpdates = sessionUpdates,
       super(const PreviewInitialState()) {
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  final PreviewRepository _repository;
  final String sessionId;
  String? previewUrl;
  final Duration _poll;
  final Stream<SseStreamEvent> Function()? _workspaceEvents;
  final Stream<SessionModel> Function()? _sessionUpdates;

  PreviewModel? preview;
  bool loading = true;
  String? error;

  Timer? _timer;
  StreamSubscription<SseStreamEvent>? _workspaceSubscription;
  StreamSubscription<SessionModel>? _sessionSubscription;
  bool _paused = false;
  bool _background = false;
  bool _refreshing = false;
  bool _refreshPending = false;
  int _generation = 0;
  int _watchGeneration = 0;
  int _revision = 0;

  bool get hasPreview => preview != null && previewWorthShowing(preview!.entry);
  bool get polling =>
      !_paused && !_background && !isClosed && sessionId.isNotEmpty;

  void _start() {
    unawaited(refresh());
    if (!polling) return;
    _sessionSubscription = _sessionUpdates?.call().listen((session) {
      if (!polling || session.id != sessionId) return;
      if (previewUrl == session.previewUrl) return;
      previewUrl = session.previewUrl;
      _generation++;
      unawaited(refresh());
    });
    _connectWorkspace();
  }

  void _connectWorkspace() {
    if (!polling) return;
    final events = _workspaceEvents;
    if (events == null) {
      _scheduleFallback();
      return;
    }
    final generation = _watchGeneration;
    _workspaceSubscription = events().listen(
      (_) {
        if (!polling || generation != _watchGeneration) return;
        _timer?.cancel();
        _timer = null;
        unawaited(refresh());
      },
      onError: (Object _) {
        if (generation == _watchGeneration) _workspaceUnavailable();
      },
      onDone: () {
        if (generation == _watchGeneration) _workspaceUnavailable();
      },
    );
  }

  void _workspaceUnavailable() {
    unawaited(_workspaceSubscription?.cancel());
    _workspaceSubscription = null;
    _scheduleFallback();
  }

  void _scheduleFallback() {
    if (!polling || _timer != null) return;
    _timer = Timer(_poll, () {
      _timer = null;
      if (!polling) return;
      unawaited(refresh());
      _connectWorkspace();
    });
  }

  void _stop() {
    _generation++;
    _watchGeneration++;
    _timer?.cancel();
    _timer = null;
    unawaited(_workspaceSubscription?.cancel());
    _workspaceSubscription = null;
    unawaited(_sessionSubscription?.cancel());
    _sessionSubscription = null;
  }

  void pausePolling() {
    if (_paused) return;
    _paused = true;
    _stop();
  }

  void resumePolling() {
    if (isClosed || !_paused) return;
    _paused = false;
    if (!_background) _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state != AppLifecycleState.resumed;
    if (_background == background) return;
    _background = background;
    if (background) {
      _stop();
    } else if (!_paused) {
      _start();
    }
  }

  Future<void> refresh() async {
    if (isClosed || _paused || _background) return;
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    if (sessionId.isEmpty) {
      loading = false;
      emit(PreviewReadyState(++_revision));
      return;
    }
    _refreshing = true;
    do {
      _refreshPending = false;
      final generation = _generation;
      final result = await _repository.getPreview(
        sessionId,
        previewUrl: previewUrl,
      );
      if (isClosed || _paused || _background) break;
      if (generation != _generation) continue;
      result.when(
        onSuccess: (value) {
          preview = value;
          error = null;
        },
        onFailure: (failure) => error = failure.message,
      );
      loading = false;
      emit(PreviewReadyState(++_revision));
    } while (_refreshPending);
    _refreshing = false;
  }

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    return super.close();
  }
}
