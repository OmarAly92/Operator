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
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockDesktopsRepository extends Mock implements DesktopsRepository {}

class _MockNotificationRepository extends Mock implements NotificationRepository {}

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
  late _MockDesktopsRepository desktopsRepository;

  setUp(() async {
    AppPreferences.debugLoad(const {});
    PackageInfo.setMockInitialValues(
      appName: 'Operator',
      packageName: 'dev.operator.mobile',
      version: '1.2.0',
      buildNumber: '42',
      buildSignature: '',
    );
    sessionsRepository = _MockSessionsRepository();
    when(() => sessionsRepository.cachedBoard()).thenAnswer((_) async => null);
    mux = _MockMuxClient();
    serverConfigStore = _MockServerConfigStore();
    desktopsRepository = _MockDesktopsRepository();
    when(() => desktopsRepository.deactivate()).thenAnswer((_) async => Result.success(null));

    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => sessionsRepository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: const BoardSnapshot())),
    );
    when(() => serverConfigStore.current).thenReturn(null);
    when(() => serverConfigStore.changes).thenAnswer((_) => const Stream.empty());

    final notificationRepository = _MockNotificationRepository();
    when(() => notificationRepository.getPhoneAlerts()).thenAnswer(
      (_) async => Result.success(const PhoneAlertStatusModel(enabled: false, claimed: false)),
    );

    await sl.reset();
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
    sl.registerFactory<PhoneAlertsCubit>(
      () => PhoneAlertsCubit(
        notificationRepository,
        launch: (_) async => true,
        copy: (_) async {},
        ntfyDeepLink: false,
      ),
    );
  });

  tearDown(() => sl.reset());

  SessionsCubit buildSessionsCubit({String activeProjectId = kAllProjects}) {
    final cubit = SessionsCubit(sessionsRepository, mux, serverConfigStore);
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
              RoutesStrings.connections: (_) =>
                  const Scaffold(body: Text('Connections screen')),
            },
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => sessionsCubit),
                BlocProvider<SkinCubit>(create: (_) => skinCubit ?? SkinCubit()),
                BlocProvider<SettingsCubit>(
                  create: (_) => SettingsCubit(sessionsRepository, serverConfigStore, desktopsRepository),
                ),
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

    await tester.dragUntilVisible(find.text('Disconnect'), find.byType(ListView), const Offset(0, -200));
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => serverConfigStore.clear());
  });

  testWidgets('confirming disconnect deactivates the desktop and navigates to the desktops list', (tester) async {
    when(() => serverConfigStore.clear()).thenAnswer((_) async {});

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(find.text('Disconnect'), find.byType(ListView), const Offset(0, -200));
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect').last);
    await tester.pumpAndSettle();

    verify(() => desktopsRepository.deactivate()).called(1);
    verify(() => serverConfigStore.clear()).called(1);
    expect(find.text('Connections screen'), findsOneWidget);
  });

  testWidgets('the Your desktops row opens the connections route', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.tap(find.text('Your desktops'));
    await tester.pumpAndSettle();

    expect(find.text('Connections screen'), findsOneWidget);
  });

  testWidgets('the History row opens the notifications route', (tester) async {
    when(() => serverConfigStore.current).thenReturn(_pairedConfig);

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());
    await tester.dragUntilVisible(find.text('History'), find.byType(ListView), const Offset(0, -200));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications screen'), findsOneWidget);
  });

  testWidgets('settings offers a token usage row', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(find.text('Token usage'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('Token usage'), findsOneWidget);
  });

  testWidgets('the Token usage row opens the usage route', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.dragUntilVisible(
      find.text('Token usage'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Token usage'));
    await tester.pumpAndSettle();

    expect(find.text('Usage screen'), findsOneWidget);
  });
}
