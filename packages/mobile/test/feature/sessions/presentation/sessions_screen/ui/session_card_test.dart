import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_pr_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';

void main() {
  testWidgets('renders title, status, PR line, and relative time, and reports taps', (tester) async {
    var tapped = false;
    var longPressed = false;
    final session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      branch: 'fix/auth-timeouts',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
      prs: const [SessionPrModel(url: 'u', number: 12, state: 'open')],
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(
                session: session,
                showProject: true,
                onTap: () => tapped = true,
                onLongPress: () => longPressed = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('PR #12 open'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);

    await tester.tap(find.byType(SessionCard));
    expect(tapped, isTrue);

    await tester.longPress(find.byType(SessionCard));
    expect(longPressed, isTrue);
  });

  Future<void> pumpCard(WidgetTester tester, SessionModel session) => tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp(
        home: SkinScope(
          skin: const DarkSkin(),
          child: Scaffold(
            body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
          ),
        ),
      ),
    ),
  );

  testWidgets('a working agent shows how long its turn has run', (tester) async {
    final since = DateTime.now().subtract(const Duration(minutes: 2, seconds: 2));
    await pumpCard(
      tester,
      SessionModel(
        id: 'proj-1',
        projectId: 'proj',
        displayName: 'Fix auth',
        status: 'working',
        activity: 'active',
        activitySince: since.toUtc().toIso8601String(),
      ),
    );
    expect(find.text('Working'), findsNothing);
    expect(find.textContaining(RegExp(r'^2m[23]s$')), findsOneWidget);
  });

  testWidgets('an agent that is not working keeps its status label', (tester) async {
    await pumpCard(
      tester,
      SessionModel(
        id: 'proj-1',
        projectId: 'proj',
        displayName: 'Fix auth',
        status: 'idle',
        activity: 'idle',
        activitySince: DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      ),
    );
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('renders no timestamp when the session has never reported one', (tester) async {
    const session = SessionModel(id: 'proj-1', projectId: 'proj', displayName: 'Fix auth', status: 'working');

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fix auth'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('renders the branch and worktree directory for a worktree session', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      branch: 'fix/auth-timeouts',
      workspaceMode: 'worktree',
      workspacePath: '/repos/proj/.worktrees/fix-auth-timeouts',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('fix/auth-timeouts'), findsOneWidget);
    expect(find.text('fix-auth-timeouts'), findsOneWidget);
    expect(find.byIcon(Icons.call_split), findsOneWidget);
  });

  testWidgets('renders the project path in place of a branch for an in-place session', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      workspaceMode: 'in_place',
      workspacePath: '/repos/proj',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('/repos/proj'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });

  testWidgets('renders both the branch and the project path for an in-place session', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      branch: 'fix/auth-timeouts',
      workspaceMode: 'in_place',
      workspacePath: '/repos/proj',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('fix/auth-timeouts'), findsOneWidget);
    expect(find.text('/repos/proj'), findsOneWidget);
    expect(find.byIcon(Icons.call_split), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });

  testWidgets('still renders the issue badge for an in-place session with no workspace path yet', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      workspaceMode: 'in_place',
      issueId: 'github:42',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('github:42'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
  });

  testWidgets('shows the agent, its Claude account and the model it last ran on', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Fix auth',
      status: 'working',
      harness: 'claude-code',
      claudeAccountId: 'personal',
      model: 'claude-sonnet-5',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(
                session: session,
                showProject: true,
                accountLabels: const {'personal': 'Personal'},
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('claude-code'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Sonnet 5'), findsOneWidget);
  });

  testWidgets('a non-Claude session shows only its agent', (tester) async {
    const session = SessionModel(id: 'proj-1', projectId: 'proj', displayName: 'Fix auth', status: 'working', harness: 'codex');

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('codex'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
  });

  testWidgets('shows the reason the agent reported for its card', (tester) async {
    const session = SessionModel(
      id: 'proj-1',
      projectId: 'proj',
      displayName: 'Pick a db',
      status: 'needs_input',
      agentReportState: 'needs_you',
      agentReportReason: 'Postgres or SQLite?',
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: SkinScope(
            skin: const DarkSkin(),
            child: Scaffold(
              body: SessionCard(session: session, showProject: true, onTap: () {}, onLongPress: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Postgres or SQLite?'), findsOneWidget);
  });
}
