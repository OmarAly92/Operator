import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockNotificationRepository extends Mock implements NotificationRepository {}

class _MemorySecureStorage implements PushSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeTokenSource implements PushTokenSource {
  @override
  bool get supported => false;

  @override
  String get platform => 'ios';

  @override
  Future<String?> deviceName() async => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<PushStatus> permissionStatus() async =>
      const PushStatus(supported: false, granted: false, canAskAgain: true, registered: false);
}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _MockNotificationRepository notificationRepository;

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
  });

  setUp(() async {
    HomeShell.selectedTab.value = 0;
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    notificationRepository = _MockNotificationRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
    when(() => notificationRepository.getNotifications(any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const NotificationPageModel(notifications: [], unreadCount: 0)),
      ),
    );
    await sl.reset();
    sl.registerFactory<PullRequestCubit>(() => PullRequestCubit(_MockPullRequestRepository()));
    sl.registerFactory<OrchestratorCubit>(() => OrchestratorCubit(_MockOrchestratorRepository()));
    final serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(null);
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
    sl.registerFactory<SettingsCubit>(() => SettingsCubit(repository, serverConfigStore));
    sl.registerLazySingleton<PushRegistrar>(
      () => PushRegistrar(
        notificationRepository,
        PushRegistrationStore(_MemorySecureStorage()),
        _FakeTokenSource(),
      ),
    );
  });

  tearDown(() => sl.reset());

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => SessionsCubit(repository, mux)),
                BlocProvider<SkinCubit>(create: (_) => SkinCubit()),
                BlocProvider<NotificationsCubit>(
                  create: (_) => NotificationsCubit(
                    notificationRepository,
                    sl<ServerConfigStore>(),
                    unreadPoll: const Duration(hours: 1),
                  ),
                ),
              ],
              child: const HomeShell(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers all four tabs', (tester) async {
    await pumpShell(tester);

    for (final label in ['Agents', 'Orchestrator', 'PRs', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('opens on the Agents tab', (tester) async {
    await pumpShell(tester);

    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex, 0);
  });

  testWidgets('switches tabs on tap', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar)).currentIndex, 3);
  });

  testWidgets('keeps every tab mounted so each keeps its state', (tester) async {
    await pumpShell(tester);

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).children.length, 4);
  });
}
