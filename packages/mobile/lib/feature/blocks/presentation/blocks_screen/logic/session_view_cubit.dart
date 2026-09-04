import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

part 'session_view_state.dart';

enum SessionViewMode { blocks, raw }

SessionViewMode defaultViewMode(TerminalArgs args) {
  if (args.shellOnly) return SessionViewMode.raw;
  return BlockHarnesses.covers(args.harness) ? SessionViewMode.blocks : SessionViewMode.raw;
}

String sessionViewKey(TerminalArgs args) => args.shellOnly ? args.id : args.sessionId;

SessionViewMode? persistedViewMode(String key) {
  final saved = CacheHelper.get(CacheKeys.sessionView(key)) as String?;
  for (final mode in SessionViewMode.values) {
    if (mode.name == saved) return mode;
  }
  return null;
}

class SessionViewCubit extends Cubit<SessionViewState> {
  SessionViewCubit(SessionViewMode initial, {this.persistKey}) : super(SessionViewReadyState(initial));

  final String? persistKey;

  SessionViewMode get mode => (state as SessionViewReadyState).mode;

  void toggle() {
    final next = mode == SessionViewMode.blocks ? SessionViewMode.raw : SessionViewMode.blocks;
    final key = persistKey;
    if (key != null && key.isNotEmpty) CacheHelper.save(CacheKeys.sessionView(key), next.name);
    emit(SessionViewReadyState(next));
  }
}
