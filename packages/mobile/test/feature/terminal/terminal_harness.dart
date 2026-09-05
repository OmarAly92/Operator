import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/pending_interaction_model.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class MockMuxClient extends Mock implements MuxClient {}

class MockTerminalRepository extends Mock implements TerminalRepository {}

class MockSessionsRepository extends Mock implements SessionsRepository {}

class MockPreviewRepository extends Mock implements PreviewRepository {}

class MockBlocksRepository extends Mock implements BlocksRepository {}

class MockSessionControlRepository extends Mock implements SessionControlRepository {}

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
  final StreamController<MuxStatus> statuses = StreamController<MuxStatus>.broadcast();
  final StreamController<TerminalEvent> events = StreamController<TerminalEvent>.broadcast();
  final StreamController<BlockEventEnvelope> blockEvents =
      StreamController<BlockEventEnvelope>.broadcast();
  final StreamController<List<SessionPatch>> sessionPatches =
      StreamController<List<SessionPatch>>.broadcast();

  late TerminalCubit cubit;
  late SessionViewCubit viewCubit;
  late BlocksCubit blocksCubit;
  late SessionCommandCubit commandCubit;

  void start({bool shellOnly = false, String? harness}) {
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
    registerFallbackValue(const GetSessionBlocksParams());
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.blockEvents).thenAnswer((_) => blockEvents.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => sessionPatches.stream);
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);

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
          : TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session', harness: harness),
    );

    final blocksRepository = MockBlocksRepository();
    when(() => blocksRepository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));

    viewCubit = SessionViewCubit(defaultViewMode(cubit.args));
    blocksCubit = BlocksCubit(mux, blocksRepository, cubit.args.sessionId, harness: harness);
    final controlRepository = MockSessionControlRepository();
    when(() => controlRepository.getInteractions(any()))
        .thenAnswer((_) async => Result.success(GlobalResponse<List<PendingInteractionModel>>()));
    commandCubit = SessionCommandCubit(mux, controlRepository, sessionId: cubit.args.sessionId);
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
                  BlocProvider<SessionViewCubit>.value(value: viewCubit),
                  BlocProvider<BlocksCubit>.value(value: blocksCubit),
                  BlocProvider<SessionCommandCubit>.value(value: commandCubit),
                  BlocProvider<PreviewCubit>(
                    create: (_) => sl<PreviewCubit>(param1: cubit.args.sessionId, param2: null),
                  ),
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
    await viewCubit.close();
    await blocksCubit.close();
    await commandCubit.close();
    await blockEvents.close();
    await sessionPatches.close();
    await cubit.close();
    await statuses.close();
    await events.close();
  }
}
