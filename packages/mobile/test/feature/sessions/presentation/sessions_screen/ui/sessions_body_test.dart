import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_section_header.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  final List<String> fired = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
    mux = _MockMuxClient();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    fired.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpBody(WidgetTester tester, BoardSnapshot snapshot) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(GlobalResponse(data: snapshot)),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => Text((settings.arguments as Map<String, dynamic>)['sessionId'] as String),
          ),
          home: SkinScope(
            skin: const DarkSkin(),
            child: BlocProvider(
              create: (_) => SessionsCubit(repository, mux),
              child: const Scaffold(body: SessionsBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups sessions into their board sections with a stat header', (tester) async {
    await pumpBody(
      tester,
      const BoardSnapshot(
        sessions: [
          SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you', status: 'needs_input'),
        ],
      ),
    );

    expect(find.text('Working one'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Working'), findsWidgets);
  });

  for (final target in const [
    (title: 'Active route', id: 'active-session', archived: false),
    (title: 'Archived route', id: 'archived-session', archived: true),
  ]) {
    testWidgets('opens the exact ${target.archived ? 'archived' : 'active'} board session id', (tester) async {
      await pumpBody(
        tester,
        BoardSnapshot(
          sessions: [
            SessionModel(
              id: target.id,
              projectId: 'proj',
              displayName: target.title,
              status: target.archived ? 'terminated' : 'working',
              isTerminated: target.archived,
            ),
          ],
        ),
      );

      if (target.archived) {
        await tester.tap(find.text('ARCHIVE'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(target.title));
      await tester.pumpAndSettle();

      expect(find.text(target.id), findsOneWidget);
    });
  }

  group('stat jump', () {
    testWidgets('tapping a populated stat clicks and jumps to its section', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
            SessionModel(id: 'b', projectId: 'proj', displayName: 'Needs you', status: 'needs_input'),
          ],
        ),
      );

      await tester.tap(find.text('need you'));
      await tester.pumpAndSettle();

      expect(fired, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('tapping a stat whose section is not on the board stays silent', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          ],
        ),
      );

      await tester.tap(find.text('mergeable'));
      await tester.pumpAndSettle();

      expect(fired, isEmpty);
    });

    testWidgets('section elements survive a board refresh', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
          ],
        ),
      );

      final before = tester.element(find.byType(SessionSectionHeader).first);

      await tester.element(find.byType(SessionsBody)).read<SessionsCubit>().refresh();
      await tester.pumpAndSettle();

      final after = tester.element(find.byType(SessionSectionHeader).first);
      expect(identical(before, after), isTrue,
          reason: 'a rebuilt GlobalKey re-inflates the section on every poll tick');
    });
  });

  group('archive', () {
    testWidgets('keeps terminated sessions collapsed until the header is tapped', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'proj', displayName: 'Working one', status: 'working'),
            SessionModel(
              id: 'b',
              projectId: 'proj',
              displayName: 'Dead one',
              status: 'terminated',
              isTerminated: true,
            ),
          ],
        ),
      );

      expect(find.text('ARCHIVE'), findsOneWidget);
      expect(find.text('Dead one'), findsNothing);

      await tester.tap(find.text('ARCHIVE'));
      await tester.pumpAndSettle();

      expect(find.text('Dead one'), findsOneWidget);
    });
  });

  group('project filter', () {
    testWidgets('names the project a persisted filter is pinned to', (tester) async {
      SharedPreferences.setMockInitialValues({'flutter.${CacheKeys.activeProjectId}': 'scratch'});
      await CacheHelper.init();

      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [
            SessionModel(id: 'a', projectId: 'scratch', displayName: 'Scratch one', status: 'working'),
            SessionModel(id: 'b', projectId: 'other', displayName: 'Other one', status: 'working'),
          ],
          projects: [ProjectModel(id: 'scratch', name: 'Scratch')],
        ),
      );

      expect(find.text('Scratch'), findsOneWidget);
      expect(find.text('Scratch one'), findsOneWidget);
      expect(find.text('Other one'), findsNothing);
    });

    testWidgets('stays hidden on an unfiltered board with a single project', (tester) async {
      await pumpBody(
        tester,
        const BoardSnapshot(
          sessions: [SessionModel(id: 'a', projectId: 'scratch', displayName: 'Scratch one', status: 'working')],
          projects: [ProjectModel(id: 'scratch', name: 'Scratch')],
        ),
      );

      expect(find.text('PROJECTS'), findsNothing);
    });
  });
}
