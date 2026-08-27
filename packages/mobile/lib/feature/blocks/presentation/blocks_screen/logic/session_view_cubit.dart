import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

part 'session_view_state.dart';

enum SessionViewMode { blocks, raw }

SessionViewMode defaultViewMode(TerminalArgs args) {
  if (args.shellOnly) return SessionViewMode.raw;
  return BlockHarnesses.covers(args.harness) ? SessionViewMode.blocks : SessionViewMode.raw;
}

class SessionViewCubit extends Cubit<SessionViewState> {
  SessionViewCubit(SessionViewMode initial) : super(SessionViewReadyState(initial));

  SessionViewMode get mode => (state as SessionViewReadyState).mode;

  void toggle() => emit(
    SessionViewReadyState(mode == SessionViewMode.blocks ? SessionViewMode.raw : SessionViewMode.blocks),
  );
}
