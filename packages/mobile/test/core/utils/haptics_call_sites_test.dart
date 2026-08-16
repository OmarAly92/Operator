import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_pill.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/theme_picker_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart';
import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';

class MockManualConnectCubit extends MockCubit<ManualConnectState> implements ManualConnectCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> fired = <String>[];

  setUp(() {
    fired.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') fired.add('${call.arguments}');
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(Haptics.channelName),
      (call) async {
        fired.add('${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
  });

  Widget host(Widget child) => SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
        ),
      );

  group('PrimaryButton haptics', () {
    testWidgets('a normal press taps', (tester) async {
      await tester.pumpWidget(host(PrimaryButton(text: 'Go', onPressed: () {})));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a destructive press warns instead', (tester) async {
      await tester.pumpWidget(
        host(PrimaryButton(text: 'Kill', isDestructive: true, onPressed: () {})),
      );
      await tester.tap(find.text('Kill'));
      await tester.pump();
      expect(fired, ['warning']);
    });

    testWidgets('a disabled button fires nothing', (tester) async {
      await tester.pumpWidget(host(const PrimaryButton(text: 'Go', onPressed: null)));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(fired, isEmpty);
    });
  });

  group('AppPill haptics', () {
    testWidgets('a tap fires exactly one selection click', (tester) async {
      await tester.pumpWidget(host(AppPill(label: 'Filter', active: false, onTap: () {})));
      await tester.tap(find.text('Filter'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('theme picker option haptics', () {
    testWidgets('picking a theme fires exactly one selection click', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showThemePickerSheet(context, selected: ThemeMode.system),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('project picker option haptics', () {
    testWidgets('picking a project fires exactly one selection click', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showProjectPickerSheet(
                context,
                projects: const [ProjectModel(id: 'p1', name: 'Project One')],
                selected: 'p1',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project One'));
      await tester.pump();
      expect(fired, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('manual connect haptics', () {
    MockManualConnectCubit stubbedCubit() {
      final cubit = MockManualConnectCubit();
      when(() => cubit.hostController).thenReturn(TextEditingController());
      when(() => cubit.portController).thenReturn(TextEditingController(text: '3011'));
      when(() => cubit.passwordController).thenReturn(TextEditingController());
      when(() => cubit.secure).thenReturn(false);
      return cubit;
    }

    testWidgets('a successful connect reports success', (tester) async {
      final cubit = stubbedCubit();
      whenListen(
        cubit,
        Stream<ManualConnectState>.fromIterable([const ConnectSuccessState()]),
        initialState: const ManualConnectInitialState(),
      );
      await tester.pumpWidget(host(
        BlocProvider<ManualConnectCubit>.value(value: cubit, child: const ManualConnectBody()),
      ));
      await tester.pump();
      expect(fired, ['success']);
    });

    testWidgets('a failed connect warns', (tester) async {
      final cubit = stubbedCubit();
      whenListen(
        cubit,
        Stream<ManualConnectState>.fromIterable([
          ConnectFailureState(describeConnectionFailure(
            ConnectionFailure.auth,
            host: 'h',
            port: '3011',
            platform: TargetPlatform.iOS,
          )),
        ]),
        initialState: const ManualConnectInitialState(),
      );
      await tester.pumpWidget(host(
        BlocProvider<ManualConnectCubit>.value(value: cubit, child: const ManualConnectBody()),
      ));
      await tester.pump();
      expect(fired, ['warning']);
    });
  });
}
