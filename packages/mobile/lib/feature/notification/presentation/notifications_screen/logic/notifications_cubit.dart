import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

part 'notifications_state.dart';

const int kNotificationPageSize = 50;

class NotificationsCubit extends Cubit<NotificationsState> {
  factory NotificationsCubit(
    NotificationRepository repository,
    ServerConfigStore serverConfigStore, {
    Duration unreadPoll = const Duration(seconds: 30),
    ConnectionSignals? connection,
  }) => NotificationsCubit._(repository, serverConfigStore, unreadPoll: unreadPoll, connection: connection);

  NotificationsCubit._(
    this._repository,
    this._serverConfigStore, {
    required this._unreadPoll,
    ConnectionSignals? connection,
  }) : _connection = connection,
       super(const NotificationsInitialState()) {
    _configSub = _serverConfigStore.changes.listen(_onConfigChanged);
    _retrySub = connection?.retries.listen((_) => unawaited(load()));
    unawaited(_start(_epoch));
    _timer = Timer.periodic(_unreadPoll, (_) => unawaited(refreshUnread()));
  }

  final NotificationRepository _repository;
  final ServerConfigStore _serverConfigStore;
  final Duration _unreadPoll;
  final ConnectionSignals? _connection;

  bool get _hasServer => hasServer(_serverConfigStore.current);

  List<NotificationModel> items = [];
  int unreadCount = 0;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;
  String? error;

  String? _nextCursor;
  Timer? _timer;
  StreamSubscription<ServerConfig?>? _configSub;
  StreamSubscription<void>? _retrySub;
  int _revision = 0;
  int _epoch = 0;
  bool _freshLoaded = false;

  void _emit() {
    if (isClosed) return;
    emit(NotificationsReadyState(++_revision));
  }

  Future<void> _start(int epoch) async {
    await _primeFromCache(epoch);
    if (isClosed || epoch != _epoch) return;
    await load();
  }

  Future<void> _primeFromCache(int epoch) async {
    if (!_hasServer) return;
    final cached = await _repository.cachedFirstPage();
    if (cached == null || isClosed || epoch != _epoch || _freshLoaded) return;
    items = cached.value.notifications;
    _nextCursor = cached.value.nextCursor;
    unreadCount = cached.value.unreadCount;
    loading = false;
    _emit();
  }

  void _onConfigChanged(ServerConfig? next) {
    if (isClosed) return;
    _epoch++;
    items = [];
    unreadCount = 0;
    _nextCursor = null;
    error = null;
    loading = true;
    _freshLoaded = false;
    _emit();
    unawaited(_start(_epoch));
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
    final epoch = _epoch;
    error = null;
    if (!_hasServer) {
      loading = false;
      _emit();
      return;
    }
    final result = await _repository.getNotifications(
      GetNotificationsParams(
        status: 'all',
        limit: kNotificationPageSize,
        cursor: reset ? null : _nextCursor,
      ),
    );
    if (isClosed || epoch != _epoch) return;
    result.when(
      onSuccess: (response) {
        final page = response.data;
        final fetched = page?.notifications ?? const <NotificationModel>[];
        if (reset) {
          items = fetched;
          _freshLoaded = true;
        } else {
          final seen = items.map((notification) => notification.id).toSet();
          items = [...items, ...fetched.where((notification) => !seen.contains(notification.id))];
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
    final connection = _connection;
    if (!_hasServer || (connection != null && (connection.authFailed || connection.rateLimited))) return;
    final epoch = _epoch;
    final result = await _repository.getNotifications(
      const GetNotificationsParams(status: 'unread', limit: 1),
    );
    if (isClosed || epoch != _epoch) return;
    result.when(
      onSuccess: (response) => unreadCount = response.data?.unreadCount ?? 0,
      onFailure: (_) {},
    );
    _emit();
  }

  Future<void> open(NotificationModel notification) async {
    final id = notification.id;
    if (id == null || notification.status != 'unread') return;
    items = items.map((item) => item.id == id ? item.copyWith(status: 'read') : item).toList();
    unreadCount = unreadCount > 0 ? unreadCount - 1 : 0;
    _emit();
    await _repository.markNotificationRead(id);
  }

  Future<void> markAllRead() async {
    final previousItems = items;
    final previousUnread = unreadCount;
    items = items.map((item) => item.copyWith(status: 'read')).toList();
    unreadCount = 0;
    _emit();

    final result = await _repository.markAllNotificationsRead();
    var failed = false;
    result.when(onSuccess: (_) {}, onFailure: (_) => failed = true);
    if (!failed) return;
    items = previousItems;
    unreadCount = previousUnread;
    _emit();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    unawaited(_configSub?.cancel());
    unawaited(_retrySub?.cancel());
    return super.close();
  }
}
