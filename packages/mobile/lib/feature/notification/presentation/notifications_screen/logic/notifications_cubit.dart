import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

part 'notifications_state.dart';

const int kNotificationPageSize = 50;

class NotificationsCubit extends Cubit<NotificationsState> {
  factory NotificationsCubit(
    NotificationRepository repository, {
    Duration unreadPoll = const Duration(seconds: 30),
  }) => NotificationsCubit._(repository, unreadPoll: unreadPoll);

  NotificationsCubit._(this._repository, {required this._unreadPoll})
    : super(const NotificationsInitialState()) {
    unawaited(load());
    _timer = Timer.periodic(_unreadPoll, (_) => unawaited(refreshUnread()));
  }

  final NotificationRepository _repository;
  final Duration _unreadPoll;

  List<NotificationModel> items = [];
  int unreadCount = 0;
  bool loading = true;
  bool loadingMore = false;
  bool refreshing = false;
  String? error;

  String? _nextCursor;
  Timer? _timer;
  int _revision = 0;

  void _emit() => emit(NotificationsReadyState(++_revision));

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
    final result = await _repository.getNotifications(
      GetNotificationsParams(
        status: 'all',
        limit: kNotificationPageSize,
        cursor: reset ? null : _nextCursor,
      ),
    );
    result.when(
      onSuccess: (response) {
        final page = response.data;
        final fetched = page?.notifications ?? const <NotificationModel>[];
        if (reset) {
          items = fetched;
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
    final result = await _repository.getNotifications(
      const GetNotificationsParams(status: 'unread', limit: 1),
    );
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
    return super.close();
  }
}
