import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/orchestrator/data/model/params/launch_orchestrator_params.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/model/params/spawn_session_params.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry_test.dart' show RecordingClient;

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockSpawnRepository extends Mock implements SpawnRepository {}

class _MockOrchestratorRepository extends Mock implements OrchestratorRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

const ServerConfig _config = ServerConfig(
  host: '10.0.0.5',
  httpPort: '3011',
  secure: false,
  password: 'secret12',
);

final String _qr = jsonEncode({
  'v': 1,
  'host': '10.0.0.5',
  'port': '3011',
  'password': 'secret12',
});

void main() {
  late RecordingClient client;

  setUpAll(() {
    registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: ''));
    registerFallbackValue(const LaunchOrchestratorParams(projectId: 'p', clean: false, mode: 'chat'));
    registerFallbackValue(
      const SpawnSessionParams(projectId: 'p', mode: 'chat', prompt: 'x', issueId: 'y', harness: 'codex'),
    );
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    TelemetryRuntime.reset();
    client = RecordingClient();
    TelemetryRuntime.init(
      client: client,
      context: const TelemetryContextInput(
        platformOs: 'ios',
        isPhysicalDevice: true,
        dev: false,
        appVersion: '1.1.0',
      ),
    );
  });

  tearDown(TelemetryRuntime.reset);

  List<String> events() => client.captures.map((capture) => capture.event).toList();

  test('a QR pairing reports paired and completes onboarding', () async {
    final repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(null);
    when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
    final cubit = PairingScanCubit(repository, store, fromOnboarding: true);

    await cubit.onScan(_qr, TargetPlatform.iOS);

    expect(events(), [MobileEvents.paired, MobileEvents.onboardingCompleted]);
    expect(client.captures.first.properties['method'], 'qr');
    expect(client.captures.first.properties['from_onboarding'], isTrue);
    await cubit.close();
  });

  test('a manual connect reports paired with method=manual', () async {
    final repository = _MockPairingRepository();
    final store = _MockServerConfigStore();
    when(() => store.current).thenReturn(_config);
    when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => Result.success(true));
    final cubit = ManualConnectCubit(repository, store);

    await cubit.connect(TargetPlatform.iOS);

    expect(events(), [MobileEvents.paired]);
    expect(client.captures.single.properties['method'], 'manual');
    await cubit.close();
  });

  testWidgets('the onboarding screen reports started on mount and skipped on Skip', (tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: const OnboardingScreen(),
            routes: {RoutesStrings.sessions: (context) => const SizedBox.shrink()},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(events(), [MobileEvents.onboardingStarted]);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(events(), [MobileEvents.onboardingStarted, MobileEvents.onboardingSkipped]);
  });

  test('the board reports connected once per open, with launch then reconnect', () async {
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    var fail = false;
    when(() => repository.getBoard()).thenAnswer(
      (_) async => fail
          ? Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: 503))
          : Result.success(const GlobalResponse(data: BoardSnapshot())),
    );
    final cubit = SessionsCubit(repository, mux);
    await Future<void>.delayed(Duration.zero);

    fail = true;
    await cubit.refresh();
    fail = false;
    await cubit.refresh();

    expect(events(), [MobileEvents.connected, MobileEvents.connected]);
    expect(
      client.captures.map((capture) => capture.properties['trigger']),
      ['launch', 'reconnect'],
    );
    await cubit.close();
  });

  test('kill and restore report their feature and outcome', () async {
    final repository = _MockSessionsRepository();
    final mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(const GlobalResponse(data: BoardSnapshot())),
    );
    when(() => repository.kill(any())).thenAnswer((_) async => Result.success(true));
    when(() => repository.restore(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'nope', message: 'nope', statusCode: 500)),
    );
    final cubit = SessionsCubit(repository, mux);
    await Future<void>.delayed(Duration.zero);
    client.captures.clear();

    await cubit.kill('s-1');
    await cubit.restore('s-1');

    expect(
      client.captures.where((capture) => capture.event == MobileEvents.featureUsed).map(
        (capture) => '${capture.properties['feature']}:${capture.properties['outcome']}',
      ),
      ['kill:succeeded', 'restore:failed'],
    );
    await cubit.close();
  });

  test('spawning reports feature_used with the spawn feature', () async {
    final repository = _MockSpawnRepository();
    when(() => repository.spawn(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'no', message: 'no', statusCode: 500)),
    );
    final cubit = SpawnCubit(repository)
      ..projectId = 'p-1'
      ..name = 'fix'
      ..prompt = 'do the thing';

    await cubit.submit();

    expect(client.captures.single.properties['feature'], 'spawn');
    expect(client.captures.single.properties['outcome'], 'failed');
    await cubit.close();
  });

  test('launching the conductor reports feature_used with the conductor feature', () async {
    final repository = _MockOrchestratorRepository();
    when(() => repository.launch(any())).thenAnswer(
      (_) async => Result.success(const GlobalResponse<OrchestratorModel>()),
    );
    final cubit = OrchestratorCubit(repository);

    await cubit.launch('p-1', clean: false);

    expect(client.captures.single.properties['feature'], 'conductor');
    expect(client.captures.single.properties['outcome'], 'succeeded');
    await cubit.close();
  });
}
