import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_stream_data_source.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';

part 'notifications_state.dart';

const int kNotificationPageSize = 50;

class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit(
    this._repository,
    this._serverConfigStore, {
    Duration unreadPoll = const Duration(minutes: 2),
    NotificationStreamDataSource? streamDataSource,
  }) : _unreadPoll = unreadPoll,
       _streamDataSource = streamDataSource,
       super(const NotificationsInitialState()) {
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        setActive(state == AppLifecycleState.resumed);
      },
    );
    unawaited(load());
    _connect();
  }

  final NotificationRepository _repository;
  final ServerConfigStore _serverConfigStore;
  final Duration _unreadPoll;
  final NotificationStreamDataSource? _streamDataSource;
  StreamSubscription<SseStreamEvent>? _stream;
  Timer? _reconnectTimer;
  late final AppLifecycleListener _lifecycle;
  bool _active = true;
  bool _streamRefreshRunning = false;
  bool _streamRefreshPending = false;
  int _reconnectSeconds = 1;
  int _dataVersion = 0;
  int _fetchVersion = 0;
  final Set<String> _pendingReads = {};
  bool _markingAll = false;

  void setActive(bool active) {
    if (_active == active || isClosed) return;
    _active = active;
    _timer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_stream?.cancel());
    _stream = null;
    if (active) {
      unawaited(_refreshFromStream());
      _connect();
    }
  }

  void _connect() {
    if (!_active || isClosed) return;
    if (_timer == null || !_timer!.isActive) {
      _timer = Timer.periodic(
        _unreadPoll,
        (_) => unawaited(_refreshFromStream()),
      );
    }
    if (_streamDataSource == null || !_hasServer) return;
    _stream = _streamDataSource.watch().listen(
      (event) {
        if (!_active || isClosed) return;
        _timer?.cancel();
        _reconnectSeconds = 1;
        unawaited(_refreshFromStream());
      },
      onError: (Object _) => _disconnected(),
      onDone: _disconnected,
    );
  }

  void _disconnected() {
    if (!_active || isClosed || (_reconnectTimer?.isActive ?? false)) return;
    unawaited(_stream?.cancel());
    _stream = null;
    _timer?.cancel();
    _timer = Timer.periodic(
      _unreadPoll,
      (_) => unawaited(_refreshFromStream()),
    );
    _reconnectTimer = Timer(Duration(seconds: _reconnectSeconds), _connect);
    _reconnectSeconds = (_reconnectSeconds * 2).clamp(1, 30);
  }

  Future<void> _refreshFromStream() async {
    _streamRefreshPending = true;
    if (_streamRefreshRunning) return;
    _streamRefreshRunning = true;
    try {
      while (_streamRefreshPending && _active && !isClosed) {
        _streamRefreshPending = false;
        await _fetch(reset: true);
      }
    } finally {
      _streamRefreshRunning = false;
    }
  }

  bool get _hasServer => hasServer(_serverConfigStore.current);

  List<NotificationModel> items = [];
  int unreadCount = 0;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;
  String? error;

  String? _nextCursor;
  Timer? _timer;
  int _revision = 0;

  void _emit() {
    if (!isClosed) emit(NotificationsReadyState(++_revision));
  }

  Future<void> load() => _fetch(reset: true);

  Future<void> refresh() async {
    refreshing = true;
    _emit();
    await _fetch(reset: true);
    refreshing = false;
    _emit();
  }

  Future<void> loadMore() async {
    if (_nextCursor == null || loadingMore) return;
    loadingMore = true;
    _emit();
    await _fetch(reset: false);
    loadingMore = false;
    _emit();
  }

  Future<void> _fetch({required bool reset}) async {
    error = null;
    if (!_hasServer) {
      loading = false;
      _emit();
      return;
    }
    final requestVersion = ++_fetchVersion;
    final dataVersion = _dataVersion;
    final result = await _repository.getNotifications(
      GetNotificationsParams(
        status: 'all',
        limit: kNotificationPageSize,
        cursor: reset ? null : _nextCursor,
      ),
    );
    if (isClosed ||
        requestVersion != _fetchVersion ||
        dataVersion != _dataVersion)
      return;
    result.when(
      onSuccess: (response) {
        _dataVersion++;
        final page = response.data;
        final fetched = page?.notifications ?? const <NotificationModel>[];
        if (reset) {
          items = fetched;
        } else {
          final seen = items.map((notification) => notification.id).toSet();
          items = [
            ...items,
            ...fetched.where((notification) => !seen.contains(notification.id)),
          ];
        }
        _nextCursor = page?.nextCursor;
        unreadCount = page?.unreadCount ?? 0;
      },
      onFailure: (failure) => error = failure.message,
    );
    loading = false;
    _emit();
  }

  Future<void> refreshUnread() async {
    if (!_hasServer) return;
    final version = _dataVersion;
    final result = await _repository.getNotifications(
      const GetNotificationsParams(status: 'unread', limit: 1),
    );
    if (isClosed || version != _dataVersion) return;
    result.when(
      onSuccess: (response) => unreadCount = response.data?.unreadCount ?? 0,
      onFailure: (_) {},
    );
    _emit();
  }

  Future<void> open(NotificationModel notification) async {
    final id = notification.id;
    if (id == null || _markingAll || _pendingReads.contains(id)) return;
    final matching = items.where((item) => item.id == id);
    if (matching.isEmpty || matching.first.status != 'unread') return;
    _pendingReads.add(id);
    final optimistic = matching.first.copyWith(status: 'read');
    items = items.map((item) => item.id == id ? optimistic : item).toList();
    final version = ++_dataVersion;
    unreadCount = unreadCount > 0 ? unreadCount - 1 : 0;
    _emit();
    final result = await _repository.markNotificationRead(id);
    _pendingReads.remove(id);
    if (isClosed) return;
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) {
        error = failure.message;
        if (items.any((item) => identical(item, optimistic))) {
          items = items
              .map((item) => identical(item, optimistic) ? notification : item)
              .toList();
          if (_dataVersion == version) unreadCount++;
        }
        _dataVersion++;
        _emit();
        emit(NotificationReadFailureState(failure));
      },
    );
  }

  Future<void> markAllRead() async {
    if (_markingAll || _pendingReads.isNotEmpty) return;
    _markingAll = true;
    final originals = <NotificationModel, NotificationModel>{};
    final previousUnread = unreadCount;
    items = items.map((item) {
      if (item.status != 'unread') return item;
      final updated = item.copyWith(status: 'read');
      originals[updated] = item;
      return updated;
    }).toList();
    final version = ++_dataVersion;
    unreadCount = 0;
    _emit();
    final result = await _repository.markAllNotificationsRead();
    _markingAll = false;
    if (isClosed) return;
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) {
        error = failure.message;
        items = items.map((item) {
          for (final entry in originals.entries) {
            if (identical(entry.key, item)) return entry.value;
          }
          return item;
        }).toList();
        if (_dataVersion == version) unreadCount = previousUnread;
        _dataVersion++;
        _emit();
        emit(NotificationReadFailureState(failure));
      },
    );
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _reconnectTimer?.cancel();
    _lifecycle.dispose();
    unawaited(_stream?.cancel());
    return super.close();
  }
}
