import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/notification/data/model/params/register_push_device_params.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

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
  bool supportedValue = false;
  bool granted = false;

  @override
  bool get supported => supportedValue;

  @override
  String get platform => 'ios';

  @override
  Future<String?> deviceName() async => 'iPhone';

  @override
  Future<String?> getToken() async => 't-1';

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<PushStatus> permissionStatus() async => PushStatus(
    supported: supportedValue,
    granted: granted,
    canAskAgain: true,
    registered: false,
  );
}

const _pairedConfig = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

class _FakePairingScreen extends StatelessWidget {
  const _FakePairingScreen({required this.onPaired});

  final VoidCallback onPaired;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () {
          onPaired();
          Navigator.of(context).pop();
        },
        child: const Text('Simulate successful pairing'),
      ),
    ),
  );
}

void main() {
  late _MockSessionsRepository sessionsRepository;
  late _MockMuxClient mux;
  late _MockServerConfigStore serverConfigStore;
  late _MockNotificationRepository notificationRepository;
  late _FakeTokenSource tokenSource;

  setUpAll(() {
    registerFallbackValue(const RegisterPushDeviceParams(token: 't'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    PackageInfo.setMockInitialValues(
      appName: 'Operator',
      packageName: 'dev.operator.mobile',
      version: '1.2.0',
      buildNumber: '42',
      buildSignature: '',
    );
    sessionsRepository = _MockSessionsRepository();
    mux = _MockMuxClient();
    serverConfigStore = _MockServerConfigStore();

    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
    );
    when(() => serverConfigStore.current).thenReturn(null);

    await sl.reset();
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);

    notificationRepository = _MockNotificationRepository();
    tokenSource = _FakeTokenSource();
    when(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    when(() => notificationRepository.unregisterPushDevice(any(), target: any(named: 'target')))
        .thenAnswer((_) async => Result.success(true));
    sl.registerLazySingleton<PushRegistrar>(
      () => PushRegistrar(
        notificationRepository,
        PushRegistrationStore(_MemorySecureStorage()),
        tokenSource,
      ),
    );
  });

  tearDown(() => sl.reset());

  SessionsCubit buildSessionsCubit({String activeProjectId = kAllProjects}) {
    final cubit = SessionsCubit(sessionsRepository, mux);
    cubit.activeProjectId = activeProjectId;
    return cubit;
  }

  Future<void> pumpBody(
    WidgetTester tester, {
    required SessionsCubit sessionsCubit,
    SkinCubit? skinCubit,
    VoidCallback? onOpenBoard,
  }) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            routes: {
              RoutesStrings.onboarding: (_) => const Scaffold(body: Text('Onboarding screen')),
              RoutesStrings.pairingScan: (_) =>
                  _FakePairingScreen(onPaired: () => when(() => serverConfigStore.current).thenReturn(_pairedConfig)),
              RoutesStrings.notifications: (_) =>
                  const Scaffold(body: Text('Notifications screen')),
              RoutesStrings.usage: (_) =>
                  const Scaffold(body: Text('Usage screen')),
            },
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => sessionsCubit),
                BlocProvider<SkinCubit>(create: (_) => skinCubit ?? SkinCubit()),
                BlocProvider<SettingsCubit>(create: (_) => SettingsCubit(sessionsRepository, serverConfigStore)),
              ],
              child: Scaffold(body: SettingsBody(onOpenBoard: onOpenBoard ?? () {})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the Connection row shows host:port when paired', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('10.0.0.5:3011'), findsOneWidget);
  });

  testWidgets('returning from pairing refreshes the Connection row without waiting for a poll tick', (tester) async {
    when(() => serverConfigStore.current).thenReturn(null);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    expect(find.text('Not connected'), findsOneWidget);

    await tester.tap(find.text('Connect Operator'));
    await tester.pumpAndSettle();
    expect(find.text('Simulate successful pairing'), findsOneWidget);

    await tester.tap(find.text('Simulate successful pairing'));
    await tester.pumpAndSettle();

    expect(find.text('10.0.0.5:3011'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('the Connection row shows Not connected when unpaired', (tester) async {
    when(() => serverConfigStore.current).thenReturn(null);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('tapping Test connection renders the plural session count', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'a'), SessionModel(id: 'b')])),
      ),
    );

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected — 2 sessions'), findsOneWidget);
  });

  testWidgets('tapping Test connection renders the singular session count', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot(sessions: [SessionModel(id: 'a')]))),
    );

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected — 1 session'), findsOneWidget);
  });

  testWidgets('Test connection is disabled when unpaired', (tester) async {
    when(() => serverConfigStore.current).thenReturn(null);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connected — 0 sessions'), findsNothing);
    verify(() => sessionsRepository.getBoard()).called(1);
  });

  testWidgets('the Projects row shows the active project name', (tester) async {
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const BoardSnapshot(projects: [ProjectModel(id: 'p1', name: 'Alpha')])),
      ),
    );

    await pumpBody(tester, sessionsCubit: buildSessionsCubit(activeProjectId: 'p1'));

    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('the Projects row shows All projects when unscoped', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('All projects'), findsOneWidget);
  });

  testWidgets('the Theme row shows the current preference and choosing Light applies a light skin', (tester) async {
    final skinCubit = SkinCubit()..setSkin(const DarkSkin());

    await pumpBody(tester, sessionsCubit: buildSessionsCubit(), skinCubit: skinCubit);

    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(skinCubit.skin, isA<LightSkin>());
  });

  testWidgets('the About section renders the formatted version', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(
      find.text('1.2.0 (42)'),
      find.byType(ListView),
      const Offset(0, -200),
    );

    expect(find.text('1.2.0 (42)'), findsOneWidget);
  });

  testWidgets('declining the disconnect confirmation leaves the server untouched', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(
      find.text('Disconnect & forget server'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Disconnect & forget server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => serverConfigStore.clear());
  });

  testWidgets('confirming disconnect clears the server and navigates to onboarding', (tester) async {
    when(() => serverConfigStore.clear()).thenAnswer((_) async {});

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(
      find.text('Disconnect & forget server'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Disconnect & forget server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    verify(() => serverConfigStore.clear()).called(1);
    expect(find.text('Onboarding screen'), findsOneWidget);
  });

  testWidgets('the push switch is off and explains itself with no Firebase configuration', (
    tester,
  ) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('Agent notifications'), findsOneWidget);
    expect(find.text('Push notifications need a physical device.'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('the History row opens the notifications route', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications screen'), findsOneWidget);
  });

  testWidgets('settings offers a token usage row', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('Token usage'), findsOneWidget);
  });

  testWidgets('the Token usage row opens the usage route', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('Token usage'));
    await tester.pumpAndSettle();

    expect(find.text('Usage screen'), findsOneWidget);
  });

  testWidgets('a paired, granted, unregistered device offers a live switch', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text("This device isn't registered with your server yet."), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('turning the switch on registers the device', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    verify(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .called(1);
    expect(find.text("You'll be alerted when an agent needs you or a PR is ready."), findsOneWidget);
  });

  testWidgets('a rejected registration explains the server, not the build', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);
    tokenSource
      ..supportedValue = true
      ..granted = true;
    when(() => notificationRepository.registerPushDevice(any(), target: any(named: 'target')))
        .thenAnswer(
          (_) async => Result.failure(ServerFailure(error: 'x', message: 'no', statusCode: 401)),
        );

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Your Operator server rejected the request'), findsOneWidget);
  });
}
