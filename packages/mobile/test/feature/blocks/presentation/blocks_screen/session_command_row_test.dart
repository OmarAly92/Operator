import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/session_command_row.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';

import '../../../terminal/terminal_harness.dart';

class MockSessionCommandCubit extends Mock implements SessionCommandCubit {}

class MockSessionControlRepository extends Mock implements SessionControlRepository {}

void _stubBloc(MockSessionCommandCubit cubit) {
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.state).thenReturn(const SessionCommandState());
  when(() => cubit.close()).thenAnswer((_) async {});
}

Widget _host({required String activity, MockSessionCommandCubit? cubit}) {
  final commandCubit =
      cubit ?? (SessionCommandCubit(MockSessionControlRepository(), sessionId: 's-1')..onActivity(activity));
  if (cubit != null) _stubBloc(cubit);

  return SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: BlocProvider<SessionCommandCubit>.value(
            value: commandCubit,
            child: const SessionCommandRow(),
          ),
        ),
      ),
    ),
  );
}

final _harnesses = <TerminalHarness>[];

Widget _terminalBody({required SessionViewMode mode}) {
  final harness = TerminalHarness()..start(harness: mode == SessionViewMode.blocks ? 'claude-code' : null);
  _harnesses.add(harness);

  return SkinScope(
    skin: const DarkSkin(),
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TerminalCubit>.value(value: harness.cubit),
              BlocProvider<SessionViewCubit>.value(value: harness.viewCubit),
              BlocProvider<BlocksCubit>.value(value: harness.blocksCubit),
              BlocProvider<SessionCommandCubit>.value(value: harness.commandCubit),
              BlocProvider<PreviewCubit>(
                create: (_) => sl<PreviewCubit>(param1: harness.cubit.args.sessionId, param2: null),
              ),
            ],
            child: const TerminalBody(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() async {
    for (final harness in _harnesses) {
      await harness.dispose();
    }
    _harnesses.clear();
  });

  testWidgets('the row renders three buttons in every session state', (tester) async {
    for (final activity in ['idle', 'active', 'blocked']) {
      await tester.pumpWidget(_host(activity: activity));
      expect(find.byType(SessionCommandButton), findsNWidgets(3));
    }
  });

  testWidgets('the row height does not change with session state', (tester) async {
    await tester.pumpWidget(_host(activity: 'idle'));
    final idle = tester.getSize(find.byType(SessionCommandRow));

    await tester.pumpWidget(_host(activity: 'blocked'));
    await tester.pumpAndSettle();
    final blocked = tester.getSize(find.byType(SessionCommandRow));

    expect(blocked, idle, reason: 'a reflowing row is the thing the fixed key row exists to avoid');
  });

  testWidgets('tapping a disabled button shows why instead of calling the cubit', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn(const {});
    when(() => cubit.enabled('stop')).thenReturn(true);
    when(() => cubit.enabled('compact')).thenReturn(false);
    when(() => cubit.enabled('model')).thenReturn(false);
    when(() => cubit.disabledReason('compact')).thenReturn('The agent is working');
    when(() => cubit.disabledReason('model')).thenReturn('The agent is working');

    await tester.pumpWidget(_host(activity: 'active', cubit: cubit));
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();

    expect(find.text('The agent is working'), findsOneWidget);
    verifyNever(() => cubit.run(any()));
  });

  testWidgets('tapping stop while active runs the command', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn(const {});
    when(() => cubit.enabled('stop')).thenReturn(true);
    when(() => cubit.enabled('compact')).thenReturn(false);
    when(() => cubit.enabled('model')).thenReturn(false);
    when(() => cubit.run(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_host(activity: 'active', cubit: cubit));
    await tester.tap(find.text('Stop'));
    await tester.pump();

    verify(() => cubit.run('stop')).called(1);
  });

  testWidgets('tapping model opens the picker rather than running immediately', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn(const {});
    when(() => cubit.enabled('stop')).thenReturn(false);
    when(() => cubit.enabled('compact')).thenReturn(true);
    when(() => cubit.enabled('model')).thenReturn(true);
    when(() => cubit.models).thenReturn(['sonnet', 'opus']);

    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.byType(ModelPickerSheet), findsOneWidget);
    verifyNever(() => cubit.run(any(), model: any(named: 'model')));
  });

  testWidgets('picking a model runs the command with that label', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn(const {});
    when(() => cubit.enabled('stop')).thenReturn(false);
    when(() => cubit.enabled('compact')).thenReturn(true);
    when(() => cubit.enabled('model')).thenReturn(true);
    when(() => cubit.models).thenReturn(['sonnet', 'opus']);
    when(() => cubit.run(any(), model: any(named: 'model'))).thenAnswer((_) async {});

    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('opus'));
    await tester.pumpAndSettle();

    verify(() => cubit.run('model', model: 'opus')).called(1);
  });

  testWidgets('an unconfirmed command is visibly distinct from a confirmed one', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn({'compact': CommandPhase.unconfirmed});
    when(() => cubit.enabled('stop')).thenReturn(false);
    when(() => cubit.enabled('compact')).thenReturn(true);
    when(() => cubit.enabled('model')).thenReturn(true);
    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a disabled button renders muted, an enabled one renders full colour', (tester) async {
    final cubit = MockSessionCommandCubit();
    when(() => cubit.phases).thenReturn(const {});
    when(() => cubit.enabled('stop')).thenReturn(false);
    when(() => cubit.enabled('compact')).thenReturn(true);
    when(() => cubit.enabled('model')).thenReturn(true);

    await tester.pumpWidget(_host(activity: 'idle', cubit: cubit));

    final skin = const DarkSkin();
    final stopText = tester.widget<Text>(
      find.descendant(of: find.widgetWithText(SessionCommandButton, 'Stop'), matching: find.byType(Text)),
    );
    final compactText = tester.widget<Text>(
      find.descendant(of: find.widgetWithText(SessionCommandButton, 'Compact'), matching: find.byType(Text)),
    );

    expect(stopText.style?.color, skin.textFaint);
    expect(compactText.style?.color, isNot(skin.textFaint));
  });

  testWidgets('the row is absent in raw mode and present in blocks mode', (tester) async {
    await tester.pumpWidget(_terminalBody(mode: SessionViewMode.raw));
    expect(find.byType(SessionCommandRow), findsNothing);
    expect(find.byType(TerminalKeyRow), findsOneWidget);

    await tester.pumpWidget(_terminalBody(mode: SessionViewMode.blocks));
    await tester.pumpAndSettle();
    expect(find.byType(SessionCommandRow), findsOneWidget);
    expect(find.byType(TerminalKeyRow), findsNothing);
  });
}
