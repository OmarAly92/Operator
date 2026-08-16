import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_model.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notification_bell.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/widgets/notifications_body.dart';

class _MockRepository extends Mock implements NotificationRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

const _pairedServer = ServerConfig(
  host: '10.0.0.5',
  httpPort: '4317',
  secure: false,
  password: 'secret',
);

NotificationModel item(String id, {String type = 'needs_input', String status = 'unread'}) =>
    NotificationModel(
      id: id,
      type: type,
      sessionId: 's-1',
      title: 'Agent needs you',
      body: 'Approve the plan',
      status: status,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

void main() {
  late _MockRepository repository;
  late _MockServerConfigStore serverConfigStore;

  setUpAll(() => registerFallbackValue(const GetNotificationsParams()));

  setUp(() {
    repository = _MockRepository();
    serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(_pairedServer);
  });

  void stubPage(List<NotificationModel> notifications, {int unreadCount = 0}) {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: NotificationPageModel(notifications: notifications, unreadCount: unreadCount),
        ),
      ),
    );
  }

  Future<NotificationsCubit> pump(WidgetTester tester, Widget child) async {
    final cubit = NotificationsCubit(
      repository,
      serverConfigStore,
      unreadPoll: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) =>
                MaterialPageRoute(builder: (_) => const SizedBox(), settings: settings),
            home: Scaffold(
              body: BlocProvider<NotificationsCubit>.value(value: cubit, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('shows each notification with its label, body and stamp', (tester) async {
    stubPage([item('n-1'), item('n-2', type: 'pr_merged', status: 'read')], unreadCount: 1);

    final cubit = await pump(tester, const NotificationsBody());

    expect(find.text('Agent needs you'), findsNWidgets(2));
    expect(find.text('Approve the plan'), findsNWidgets(2));
    expect(find.text('now'), findsNWidgets(2));
    await cubit.close();
  });

  testWidgets('falls back to the type label when a record has no title', (tester) async {
    stubPage([const NotificationModel(id: 'n-1', type: 'ready_to_merge', status: 'read')]);

    final cubit = await pump(tester, const NotificationsBody());

    expect(find.text('Ready to merge'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('offers the empty state when nothing has arrived', (tester) async {
    stubPage(const []);

    final cubit = await pump(tester, const NotificationsBody());

    expect(find.text('Nothing yet'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('reports a load failure without pretending the list is empty', (tester) async {
    when(() => repository.getNotifications(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'down', statusCode: 503)),
    );

    final cubit = await pump(tester, const NotificationsBody());

    expect(find.text("Couldn't load notifications"), findsOneWidget);
    expect(find.text('down'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('tapping an unread row marks it read', (tester) async {
    stubPage([item('n-1')], unreadCount: 1);
    when(() => repository.markNotificationRead(any()))
        .thenAnswer((_) async => Result.success(true));

    final cubit = await pump(tester, const NotificationsBody());
    await tester.tap(find.text('Agent needs you'));
    await tester.pumpAndSettle();

    expect(cubit.items.single.status, 'read');
    await cubit.close();
  });

  testWidgets('the bell shows the unread count and hides the badge at zero', (tester) async {
    stubPage([item('n-1')], unreadCount: 3);

    final cubit = await pump(tester, const NotificationBell());
    expect(find.text('3'), findsOneWidget);

    stubPage([item('n-1')], unreadCount: 0);
    await cubit.refreshUnread();
    await tester.pumpAndSettle();

    expect(find.text('3'), findsNothing);
    await cubit.close();
  });
}
