import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
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
