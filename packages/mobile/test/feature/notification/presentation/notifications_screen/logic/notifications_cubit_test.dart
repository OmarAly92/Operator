import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';

class _MockRepository extends Mock implements NotificationRepository {}

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

void main() {
  late _MockRepository repository;

  setUpAll(() => registerFallbackValue(const GetNotificationsParams()));

  setUp(() => repository = _MockRepository());

  NotificationsCubit build() =>
      NotificationsCubit(repository, unreadPoll: const Duration(hours: 1));

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
}
