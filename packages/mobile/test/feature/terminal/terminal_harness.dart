import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class MockMuxClient extends Mock implements MuxClient {}

class MockTerminalRepository extends Mock implements TerminalRepository {}

class MockSessionsRepository extends Mock implements SessionsRepository {}

class MockPreviewRepository extends Mock implements PreviewRepository {}

class MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}

class _InertVoiceProvider implements VoiceProvider {
  @override
  bool get available => false;

  @override
  String? get language => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start(VoiceCallbacks callbacks, {VoiceMode mode = VoiceMode.push}) async {}

  @override
  void stop() {}

  @override
  void abort() {}
}

class TerminalHarness {
  final MockMuxClient mux = MockMuxClient();
  final MockTerminalRepository terminalRepository = MockTerminalRepository();
  final MockSessionsRepository sessionsRepository = MockSessionsRepository();
  final MockInterfaceSwitchCubit switchCubit = MockInterfaceSwitchCubit();
  final StreamController<MuxStatus> statuses = StreamController<MuxStatus>.broadcast();
  final StreamController<TerminalEvent> events = StreamController<TerminalEvent>.broadcast();

  late TerminalCubit cubit;

  void start({bool shellOnly = false}) {
    if (!sl.isRegistered<VoiceInputCubit>()) {
      sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
        (onTranscript, _) => VoiceInputCubit(_InertVoiceProvider(), onTranscript: onTranscript),
      );
    }
    if (!sl.isRegistered<PreviewCubit>()) {
      final previewRepository = MockPreviewRepository();
      when(
        () => previewRepository.getPreview(any(), previewUrl: any(named: 'previewUrl')),
      ).thenAnswer((_) async => Result.success(null));
      sl.registerFactoryParam<PreviewCubit, String, String?>(
        (sessionId, previewUrl) => PreviewCubit(
          previewRepository,
          sessionId,
          previewUrl: previewUrl,
          poll: const Duration(hours: 1),
        ),
      );
    }
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
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

    cubit = TerminalCubit(
      mux,
      terminalRepository,
      sessionsRepository,
      shellOnly
          ? const TerminalArgs(
              id: 'h-1',
              sessionId: 's-1',
              title: 'Worktree shell',
              shellOnly: true,
            )
          : const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session'),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<TerminalCubit>.value(value: cubit),
                  BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
                ],
                child: SizedBox(width: 400, height: 600, child: child),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose() async {
    await cubit.close();
    await statuses.close();
    await events.close();
  }
}
