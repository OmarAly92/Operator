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
}
