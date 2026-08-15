import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/session_route/ui/session_route_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _MockTerminalRepository terminalRepository;
  late _MockInterfaceSwitchCubit switchCubit;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();

    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    switchCubit = _MockInterfaceSwitchCubit();
    when(
      () => mux.sessionPatches,
    ).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.terminalEvents).thenAnswer((_) => const Stream<TerminalEvent>.empty());
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);

    when(() => switchCubit.state).thenReturn(const InterfaceSwitchInitialState());
    when(() => switchCubit.supported).thenReturn(true);
    when(() => switchCubit.reason).thenReturn(null);
    when(() => switchCubit.error).thenReturn(null);
    when(() => switchCubit.active).thenReturn(false);
    when(() => switchCubit.cancellable).thenReturn(false);
    when(() => switchCubit.cancelling).thenReturn(false);
    when(() => switchCubit.phase).thenReturn(null);
    when(() => switchCubit.start(any(), any())).thenAnswer((_) async {});
    when(() => switchCubit.cancel()).thenAnswer((_) async {});

    await sl.reset();
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>(
      (args, _) => TerminalCubit(mux, terminalRepository, repository, args),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pumpRoute(
    WidgetTester tester, {
    required List<SessionModel> sessions,
  }) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
      ),
    );

    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>(create: (_) => SessionsCubit(repository, mux)),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }

  Future<SessionsCubit> settledCubit(List<SessionModel> sessions) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: BoardSnapshot(sessions: sessions)),
      ),
    );
    final cubit = SessionsCubit(repository, mux);
    await cubit.stream.firstWhere((state) => state is GetSessionsSuccessState);
    clearInteractions(repository);
    return cubit;
  }

  Future<void> pumpSettledRoute(
    WidgetTester tester,
    SessionsCubit cubit,
  ) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SessionsCubit>.value(value: cubit),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: const SessionRouteScreen(sessionId: 'w-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders the terminal for a tui session', (tester) async {
    await pumpRoute(
      tester,
      sessions: const [SessionModel(id: 'w-1', projectId: 'p', mode: 'tui')],
    );

    expect(find.byType(TerminalScreen), findsOneWidget);
    expect(find.text('Terminal UI is not in this build yet'), findsNothing);
  });

  testWidgets('reports a session the daemon does not have', (tester) async {
    await pumpRoute(tester, sessions: const []);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Session not found.'), findsOneWidget);
    verify(() => repository.getBoard()).called(1);
  });

  testWidgets('refreshes a settled empty cache once before reporting the session missing', (tester) async {
    final cubit = await settledCubit(const []);
    try {
      await pumpSettledRoute(tester, cubit);

      expect(find.text('Session not found.'), findsOneWidget);
      verify(() => repository.getBoard()).called(1);
    } finally {
      await cubit.close();
    }
  });

  testWidgets('uses a cached session without another board refresh', (tester) async {
    final cubit = await settledCubit(
      const [SessionModel(id: 'w-1', projectId: 'p', mode: 'tui')],
    );
    try {
      await pumpSettledRoute(tester, cubit);

      expect(find.byType(TerminalScreen), findsOneWidget);
      verifyNever(() => repository.getBoard());
    } finally {
      await cubit.close();
    }
  });
}
