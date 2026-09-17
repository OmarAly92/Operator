import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/terminal/data/model/slash_command_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart';

class _MockSlashMenuCubit extends MockCubit<SlashMenuState> implements SlashMenuCubit {}

const _compact = SlashCommandModel(name: 'compact', description: 'Keep a summary', source: 'builtin');
const _analyze = SlashCommandModel(name: 'sc:analyze', description: 'Analyze', source: 'user');
const _model = SlashCommandModel(name: 'model', description: 'Pick a model', source: 'builtin', interactive: true);

Widget _host(SlashMenuCubit cubit) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: Scaffold(body: BlocProvider<SlashMenuCubit>.value(value: cubit, child: const SlashCommandMenu())),
    ),
  ),
);

void main() {
  setUpAll(() => registerFallbackValue(_compact));

  testWidgets('renders nothing while closed', (tester) async {
    final cubit = _MockSlashMenuCubit();
    when(() => cubit.state).thenReturn(const SlashMenuChangedState(open: false, matches: []));
    when(() => cubit.open).thenReturn(false);
    when(() => cubit.matches).thenReturn(const []);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/compact'), findsNothing);
  });

  testWidgets('lists matches and picks on tap', (tester) async {
    final cubit = _MockSlashMenuCubit();
    when(() => cubit.state).thenReturn(const SlashMenuChangedState(open: true, matches: [_compact, _analyze]));
    when(() => cubit.open).thenReturn(true);
    when(() => cubit.matches).thenReturn(const [_compact, _analyze]);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('Keep a summary'), findsOneWidget);
    expect(find.text('/sc:analyze'), findsOneWidget);
    expect(find.text('user'), findsOneWidget);
    expect(find.text('builtin'), findsNothing);

    await tester.tap(find.text('/sc:analyze'));
    verify(() => cubit.pick(_analyze)).called(1);
  });

  testWidgets('an interactive command is tagged desktop and never picked', (tester) async {
    final cubit = _MockSlashMenuCubit();
    when(() => cubit.state).thenReturn(const SlashMenuChangedState(open: true, matches: [_compact, _model]));
    when(() => cubit.open).thenReturn(true);
    when(() => cubit.matches).thenReturn(const [_compact, _model]);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/model'), findsOneWidget);
    expect(find.text('desktop'), findsOneWidget);

    await tester.tap(find.text('/model'));
    await tester.pump();
    verifyNever(() => cubit.pick(any()));
    expect(find.text('Run /model on the desktop'), findsOneWidget);
  });

  testWidgets('a long list scrolls inside a capped height', (tester) async {
    final cubit = _MockSlashMenuCubit();
    final many = [for (var i = 0; i < 30; i++) SlashCommandModel(name: 'cmd$i', description: 'Command $i', source: 'builtin')];
    when(() => cubit.state).thenReturn(SlashMenuChangedState(open: true, matches: many));
    when(() => cubit.open).thenReturn(true);
    when(() => cubit.matches).thenReturn(many);

    await tester.pumpWidget(_host(cubit));

    expect(find.text('/cmd0'), findsOneWidget);
    expect(find.text('/cmd29'), findsNothing);
    expect(tester.getSize(find.byType(ListView)).height, lessThanOrEqualTo(300));

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('/cmd29'), findsOneWidget);
  });
}
