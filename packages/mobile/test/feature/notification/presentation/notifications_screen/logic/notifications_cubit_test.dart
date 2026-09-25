import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/connection/connection_signals.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';

class _MockRepository extends Mock implements NotificationRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

const _pairedServer = ServerConfig(
  host: '10.0.0.5',
  httpPort: '4317',
  secure: false,
  password: 'secret',
);

NotificationModel item(String id, {String status = 'unread'}) =>
    NotificationModel(id: id, type: 'needs_input', sessionId: 's-1', status: status);

Result<GlobalResponse<NotificationPageModel>, Failure> page(
  List<NotificationModel> notifications, {
  String? nextCursor,
  int unreadCount = 0,
}) => Result.success(
  GlobalResponse(
    data: NotificationPageModel(
      notifications: notifications,
      nextCursor: nextCursor,
      unreadCount: unreadCount,
    ),
  ),
);

class _Signals implements ConnectionSignals {
  _Signals(this.retries);

  @override
  final Stream<void> retries;

  @override
  bool authFailed = false;

  @override
  bool rateLimited = false;
}

void main() {
  late _MockRepository repository;
  late _MockServerConfigStore serverConfigStore;
  late StreamController<ServerConfig?> changes;

  setUpAll(() => registerFallbackValue(const GetNotificationsParams()));

  setUp(() {
    repository = _MockRepository();
    serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(_pairedServer);
    changes = StreamController<ServerConfig?>.broadcast(sync: true);
    when(() => serverConfigStore.changes).thenAnswer((_) => changes.stream);
    when(() => repository.cachedFirstPage()).thenAnswer((_) async => null);
  });

  tearDown(() => changes.close());

  NotificationsCubit build() =>
      NotificationsCubit(repository, serverConfigStore, unreadPoll: const Duration(hours: 1));

  test('loads the first page on construction', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.items.single.id, 'n-1');
    expect(cubit.unreadCount, 1);
    expect(cubit.loading, isFalse);
    final captured = verify(() => repository.getNotifications(captureAny())).captured.single
        as GetNotificationsParams;
    expect(captured.status, 'all');
    expect(captured.limit, kNotificationPageSize);
    expect(captured.cursor, isNull);
    await cubit.close();
  });

  test('keeps the error message and the empty list when the first load fails', () async {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    expect(cubit.items, isEmpty);
    expect(cubit.error, 'down');
    expect(cubit.loading, isFalse);
    await cubit.close();
  });

  test('appends the next page and drops ids it already has', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], nextCursor: 'c-2', unreadCount: 2));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1'), item('n-2')], unreadCount: 2));
    await cubit.loadMore();

    expect(cubit.items.map((notification) => notification.id), ['n-1', 'n-2']);
    await cubit.close();
  });

  test('does nothing when there is no next cursor', () async {
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-1')]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.loadMore();

    verifyNever(() => repository.getNotifications(any()));
    await cubit.close();
  });

  test('refreshing replaces the list rather than appending to it', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], nextCursor: 'c-2'));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-9')]));
    await cubit.refresh();

    expect(cubit.items.map((notification) => notification.id), ['n-9']);
    await cubit.close();
  });

  test('opening an unread row marks it read optimistically and decrements the count', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    when(() => repository.markNotificationRead(any()))
        .thenAnswer((_) async => Result.success(true));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.open(cubit.items.single);

    expect(cubit.items.single.status, 'read');
    expect(cubit.unreadCount, 0);
    verify(() => repository.markNotificationRead('n-1')).called(1);
    await cubit.close();
  });

  test('opening a row that is already read does not call the daemon', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1', status: 'read')]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.open(cubit.items.single);

    verifyNever(() => repository.markNotificationRead(any()));
    await cubit.close();
  });

  test('a failed mark-all puts the truth back on screen', () async {
    when(() => repository.getNotifications(any()))
        .thenAnswer((_) async => page([item('n-1')], unreadCount: 1));
    when(() => repository.markAllNotificationsRead()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'nope', statusCode: 500)),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.markAllRead();

    expect(cubit.items.single.status, 'unread');
    expect(cubit.unreadCount, 1);
    await cubit.close();
  });

  test('does not call the daemon when there is no paired server', () async {
    when(() => serverConfigStore.current).thenReturn(null);
    final cubit = build();

    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.getNotifications(any()));
    expect(cubit.items, isEmpty);
    expect(cubit.loading, isFalse);
    await cubit.close();
  });

  test('refreshUnread is a no-op when there is no paired server', () async {
    when(() => serverConfigStore.current).thenReturn(null);
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    await cubit.refreshUnread();

    verifyNever(() => repository.getNotifications(any()));
    await cubit.close();
  });

  group('replica', () {
    const serverB = ServerConfig(host: '10.0.0.9', httpPort: '4317', secure: false, password: 'secret', desktopId: 'b');

    Replicated<NotificationPageModel> cachedPage(String id, {int unread = 0}) => Replicated(
      value: NotificationPageModel(notifications: [item(id)], unreadCount: unread),
      fetchedAt: DateTime.utc(2026, 9, 25, 8),
    );

    test('paints the cached first page and its unread count before the network answers', () async {
      final gate = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      when(() => repository.cachedFirstPage()).thenAnswer((_) async => cachedPage('n-cached', unread: 3));
      when(() => repository.getNotifications(any())).thenAnswer((_) => gate.future);

      final cubit = build();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items.single.id, 'n-cached');
      expect(cubit.unreadCount, 3);
      expect(cubit.loading, isFalse);

      gate.complete(page([item('n-fresh')], unreadCount: 1));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items.single.id, 'n-fresh');
      expect(cubit.unreadCount, 1);
      await cubit.close();
    });

    test('a desktop switch clears the previous list at once and paints the new desktop cache', () async {
      when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-a')], unreadCount: 1));
      final cubit = build();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.items.single.id, 'n-a');

      final gate = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      when(() => repository.cachedFirstPage()).thenAnswer((_) async => cachedPage('n-b-cached'));
      when(() => repository.getNotifications(any())).thenAnswer((_) => gate.future);
      when(() => serverConfigStore.current).thenReturn(serverB);
      changes.add(serverB);

      expect(cubit.items, isEmpty);
      expect(cubit.unreadCount, 0);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.items.single.id, 'n-b-cached');
      await cubit.close();
    });

    test('a fetch that started for the previous desktop is dropped', () async {
      final first = Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>();
      var calls = 0;
      when(() => repository.getNotifications(any())).thenAnswer((_) {
        calls++;
        return calls == 1 ? first.future : Completer<Result<GlobalResponse<NotificationPageModel>, Failure>>().future;
      });
      final cubit = build();
      await Future<void>.delayed(Duration.zero);

      when(() => serverConfigStore.current).thenReturn(serverB);
      changes.add(serverB);
      first.complete(page([item('n-a')], unreadCount: 5));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.items, isEmpty);
      expect(cubit.unreadCount, 0);
      await cubit.close();
    });
  });

  test('a connection retry reloads the list', () async {
    final retries = StreamController<void>.broadcast();
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([item('n-1')]));
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
      connection: _Signals(retries.stream),
    );
    await Future<void>.delayed(Duration.zero);

    retries.add(null);
    await Future<void>.delayed(Duration.zero);

    verify(() => repository.getNotifications(any())).called(2);
    await cubit.close();
    await retries.close();
  });

  test('the unread poll holds while re-pairing is needed, so it spends no auth attempts', () async {
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([]));
    final signals = _Signals(const Stream.empty())..authFailed = true;
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
      connection: signals,
    );
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.refreshUnread();

    verifyNever(() => repository.getNotifications(any()));
    await cubit.close();
  });

  test('the unread poll holds while the desktop is rate limiting', () async {
    when(() => repository.getNotifications(any())).thenAnswer((_) async => page([]));
    final signals = _Signals(const Stream.empty())..rateLimited = true;
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
      connection: signals,
    );
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.refreshUnread();
    verifyNever(() => repository.getNotifications(any()));

    signals.rateLimited = false;
    await cubit.refreshUnread();
    verify(() => repository.getNotifications(any())).called(1);
    await cubit.close();
  });
}
