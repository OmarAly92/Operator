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
import 'package:operator_mobile/core/utils/service_locator.dart';
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

    expect(find.text('1.2.0 (42)'), findsOneWidget);
  });

  testWidgets('declining the disconnect confirmation leaves the server untouched', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.tap(find.text('Disconnect & forget server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => serverConfigStore.clear());
  });

  testWidgets('confirming disconnect clears the server and navigates to onboarding', (tester) async {
    when(() => serverConfigStore.clear()).thenAnswer((_) async {});

    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    await tester.tap(find.text('Disconnect & forget server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    verify(() => serverConfigStore.clear()).called(1);
    expect(find.text('Onboarding screen'), findsOneWidget);
  });

  testWidgets('no Notifications section is present', (tester) async {
    await pumpBody(tester, sessionsCubit: buildSessionsCubit());

    expect(find.text('Agent notifications'), findsNothing);
  });
}
