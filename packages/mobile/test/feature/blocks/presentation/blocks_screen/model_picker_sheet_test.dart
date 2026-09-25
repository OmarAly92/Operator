import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';

class _MockSessionCommandCubit extends Mock implements SessionCommandCubit {}

_MockSessionCommandCubit _cubit({required bool modelEnabled, List<String> models = const []}) {
  final cubit = _MockSessionCommandCubit();
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.state).thenReturn(const SessionCommandState());
  when(() => cubit.close()).thenAnswer((_) async {});
  when(() => cubit.fetchModels()).thenAnswer((_) async {});
  when(() => cubit.isClosed).thenReturn(false);
  when(() => cubit.phases).thenReturn(const {});
  when(() => cubit.enabled('model')).thenReturn(modelEnabled);
  when(() => cubit.models).thenReturn(models);
  return cubit;
}

Widget _host(SessionCommandCubit cubit) => SkinScope(
  skin: const DarkSkin(),
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, _) => MaterialApp(
      home: Scaffold(
        body: BlocProvider<SessionCommandCubit>.value(
          value: cubit,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModelPicker(context, harness: 'claude-code'),
              child: const Text('Model'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a disabled model command shows why instead of opening the picker', (tester) async {
    final cubit = _cubit(modelEnabled: false);
    when(() => cubit.disabledReason('model')).thenReturn('The agent is working');

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.text('The agent is working'), findsOneWidget);
    expect(find.byType(ModelPickerSheet), findsNothing);
    verifyNever(() => cubit.run(any(), model: any(named: 'model')));
  });

  testWidgets('opening the picker does not run the command', (tester) async {
    final cubit = _cubit(modelEnabled: true, models: ['sonnet', 'opus']);

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.byType(ModelPickerSheet), findsOneWidget);
    verifyNever(() => cubit.run(any(), model: any(named: 'model')));
  });

  testWidgets('the picker falls back to harness placeholders when the daemon has listed none', (tester) async {
    final cubit = _cubit(modelEnabled: true);

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.text('sonnet'), findsOneWidget);
    expect(find.text('opus'), findsOneWidget);
  });

  testWidgets('picking a model runs the command with that label', (tester) async {
    final cubit = _cubit(modelEnabled: true, models: ['sonnet', 'opus']);
    when(() => cubit.run(any(), model: any(named: 'model'))).thenAnswer((_) async {});

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('opus'));
    await tester.pumpAndSettle();

    verify(() => cubit.run('model', model: 'opus')).called(1);
  });

  testWidgets('the picker marks the current model and does not re-send it', (tester) async {
    final cubit = _cubit(modelEnabled: true, models: ['Opus (1M context)', 'Sonnet']);
    when(() => cubit.state).thenReturn(
      const SessionCommandState(
        modelOptions: [
          SessionModelOptionModel(label: 'Opus (1M context)', description: 'Opus 5 with 1M context'),
          SessionModelOptionModel(label: 'Sonnet', description: 'Sonnet 5 · Efficient for routine tasks', current: true),
        ],
        currentModel: 'Sonnet',
      ),
    );

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.text('Sonnet 5 · Efficient for routine tasks'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('Sonnet'));
    await tester.pumpAndSettle();
    verifyNever(() => cubit.run(any(), model: any(named: 'model')));
  });
}
