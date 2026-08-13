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
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_actions_sheet.dart';
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
    when(() => repository.getBoard()).thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
    when(() => repository.kill(any())).thenAnswer((_) async => Result.success(true));
    when(() => repository.restore(any())).thenAnswer((_) async => Result.success(true));
  });

  Future<void> openSheet(WidgetTester tester, SessionModel session) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showSessionActionsSheet(context, session),
                    child: const Text('open actions'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers Kill for a live session', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', displayName: 'Live one', status: 'working'));

    expect(find.text('Live one'), findsOneWidget);
    expect(find.text('Kill'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('offers Restore for a session flagged terminated', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', status: 'working', isTerminated: true));

    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Kill'), findsNothing);
  });

  testWidgets('offers Restore for a session whose status is terminated', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', status: 'terminated'));

    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Kill'), findsNothing);
  });

  testWidgets('restore runs without a confirmation dialog', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', status: 'terminated'));

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    verify(() => repository.restore('proj-1')).called(1);
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('kill runs only after the confirmation is accepted', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', status: 'working'));

    await tester.tap(find.text('Kill'));
    await tester.pumpAndSettle();
    expect(find.text('Kill session?'), findsOneWidget);

    await tester.tap(find.text('Kill').last);
    await tester.pumpAndSettle();

    verify(() => repository.kill('proj-1')).called(1);
  });

  testWidgets('kill does nothing when the confirmation is declined', (tester) async {
    await openSheet(tester, const SessionModel(id: 'proj-1', status: 'working'));

    await tester.tap(find.text('Kill'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.kill(any()));
  });
}
