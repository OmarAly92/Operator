import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:xterm/xterm.dart';

part 'terminal_state.dart';

const double kTerminalMinFontSize = 7;
const double kTerminalMaxFontSize = 20;
const double kTerminalFontSize = 12;

class TerminalArgs extends Equatable {
  const TerminalArgs({
    required this.id,
    required this.sessionId,
    required this.title,
    this.projectId,
    this.shellOnly = false,
  });

  /// The PTY handle: an Operator session id, or a worktree shell's handleId.
  final String id;
  final String sessionId;
  final String title;
  final String? projectId;
  final bool shellOnly;

  @override
  List<Object?> get props => [id, sessionId, title, projectId, shellOnly];
}

class _TerminalWriteSink implements Sink<String> {
  _TerminalWriteSink(this._terminal);

  final Terminal _terminal;

  @override
  void add(String data) => _terminal.write(data);

  @override
  void close() {}
}

class TerminalCubit extends Cubit<TerminalState> {
  TerminalCubit(
    this._mux,
    this._repository,
    this._sessions,
    this.args, {
    Duration restoreDelay = const Duration(milliseconds: 1200),
  }) : _restoreDelay = restoreDelay,
       sendTarget = args.shellOnly ? SendTarget.terminal : SendTarget.agent,
       super(const TerminalInitialState()) {
    status = _mux.currentStatus;
    terminal.onOutput = (data) => _mux.sendInput(args.id, data, projectId: args.projectId);
    _statusSub = _mux.status.listen(_onStatus);
    _eventsSub = _mux.terminalEvents.where((event) => event.id == args.id).listen(_onEvent);
    _mux.openTerminal(args.id, projectId: args.projectId);
    _emit();
  }

  final MuxClient _mux;
  final TerminalRepository _repository;
  final SessionsRepository _sessions;
  final TerminalArgs args;
  final Duration _restoreDelay;

  final Terminal terminal = Terminal(maxLines: 5000);
  final TextEditingController composer = TextEditingController();

  MuxStatus status = MuxStatus.closed;
  TerminalGrid? grid;
  bool authoritative = false;
  bool notFound = false;
  bool restoring = false;
  bool sending = false;
  String? banner;
  SendTarget sendTarget;
  double fontSize = kTerminalFontSize;

  late final Sink<List<int>> _output = utf8.decoder
      .startChunkedConversion(_TerminalWriteSink(terminal));

  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<TerminalEvent>? _eventsSub;
  Timer? _reopenTimer;
  TerminalGrid? _lastFit;
  int _revision = 0;

  void _emit() => emit(TerminalReadyState(++_revision));

  void _onStatus(MuxStatus next) {
    status = next;
    _emit();
  }

  void _onEvent(TerminalEvent event) {
    switch (event) {
      case TerminalDataEvent(:final bytes):
        // Chunked so a multi-byte rune split across two frames still decodes.
        _output.add(bytes);
      case TerminalResizeEvent(:final cols, :final rows):
        authoritative = true;
        grid = TerminalGrid(cols, rows);
        terminal.resize(cols, rows);
        _emit();
      case TerminalExitedEvent(:final code):
        notFound = true;
        banner = 'Session exited (code $code)';
        _emit();
      case TerminalErrorEvent(:final message):
        // A missing PTY means the session is terminated — offer Restore instead
        // of surfacing it as a raw error banner.
        if (message.toLowerCase().contains('not found')) {
          notFound = true;
        } else {
          banner = message;
        }
        _emit();
      case TerminalOpenedEvent():
        break;
    }
  }

  /// The phone's natural grid. It is reported to the daemon so the PTY can be
  /// sized to the phone when the phone is the only viewer; it is only rendered
  /// while the daemon has not told us the authoritative size.
  void reportFit(TerminalGrid fit) {
    if (_lastFit == fit) return;
    _lastFit = fit;
    _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    if (authoritative) return;
    grid = fit;
    terminal.resize(fit.cols, fit.rows);
    _emit();
  }

  void sendKey(String sequence) =>
      _mux.sendInput(args.id, sequence, projectId: args.projectId);

  void dismissBanner() {
    banner = null;
    _emit();
  }

  @override
  Future<void> close() {
    _reopenTimer?.cancel();
    unawaited(_statusSub?.cancel());
    unawaited(_eventsSub?.cancel());
    _mux.closeTerminal(args.id, projectId: args.projectId);
    composer.dispose();
    return super.close();
  }
}
