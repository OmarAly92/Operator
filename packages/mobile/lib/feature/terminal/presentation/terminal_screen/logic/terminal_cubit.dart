import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_scroll.dart';
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
    this.previewUrl,
    this.harness,
  });

  /// The PTY handle: an Operator session id, or a worktree shell's handleId.
  final String id;
  final String sessionId;
  final String title;
  final String? projectId;
  final bool shellOnly;
  final String? previewUrl;

  /// The agent CLI running in the pane, when there is one. Decides whether a
  /// scroll gesture is reported as a wheel or sent as page keys.
  final String? harness;

  @override
  List<Object?> get props => [id, sessionId, title, projectId, shellOnly, previewUrl, harness];
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
  factory TerminalCubit(
    MuxClient mux,
    TerminalRepository repository,
    SessionsRepository sessions,
    TerminalArgs args, {
    Duration restoreDelay = const Duration(milliseconds: 1200),
  }) => TerminalCubit._(mux, repository, sessions, args, restoreDelay: restoreDelay);

  TerminalCubit._(
    this._mux,
    this._repository,
    this._sessions,
    this.args, {
    required this._restoreDelay,
  }) : sendTarget = args.shellOnly ? SendTarget.terminal : SendTarget.agent,
       super(const TerminalInitialState()) {
    status = _mux.currentStatus;
    terminal.onOutput = (data) => _mux.sendInput(args.id, data, projectId: args.projectId);
    terminal.mouseHandler = TerminalScrollRouter(terminal, harness: args.harness);
    _statusSub = _mux.status.listen(_onStatus);
    _eventsSub = _mux.terminalEvents.where((event) => event.id == args.id).listen(_onEvent);
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
  bool attached = false;
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

  void attach() {
    if (isClosed || attached) return;
    attached = true;
    _mux.openTerminal(args.id, projectId: args.projectId);
    final fit = _lastFit;
    if (fit != null) _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    _emit();
  }

  void detach() {
    if (isClosed || !attached) return;
    attached = false;
    _reopenTimer?.cancel();
    _mux.closeTerminal(args.id, projectId: args.projectId);
    _emit();
  }

  /// The phone's natural grid. It is reported to the daemon so the PTY can be
  /// sized to the phone when the phone is the only viewer; it is only rendered
  /// while the daemon has not told us the authoritative size.
  void reportFit(TerminalGrid fit) {
    if (_lastFit == fit) return;
    _lastFit = fit;
    if (!attached) return;
    _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    if (authoritative) return;
    grid = fit;
    terminal.resize(fit.cols, fit.rows);
    _emit();
  }

  void sendKey(String sequence) {
    if (!attached) return;
    _mux.sendInput(args.id, sequence, projectId: args.projectId);
  }

  void dismissBanner() {
    banner = null;
    _emit();
  }

  void setSendTarget(SendTarget target) {
    sendTarget = target;
    _emit();
  }

  void zoom(int delta) {
    fontSize = (fontSize + delta).clamp(kTerminalMinFontSize, kTerminalMaxFontSize);
    _emit();
  }

  Future<void> send() async {
    final text = composer.text.trim();
    if (text.isEmpty) return;

    if (routeForSend(sendTarget) == SendTarget.terminal) {
      if (!_writeToPty(text)) {
        Haptics.error();
        banner = kTerminalUnavailableNotice;
        _emit();
        return;
      }
      Haptics.success();
      banner = kTerminalModeNotice;
      composer.clear();
      _emit();
      return;
    }

    sending = true;
    _emit();
    final result = await _repository.sendSessionMessage(
      args.sessionId,
      SendSessionMessageParams(message: text),
    );
    result.when(
      onSuccess: (_) {
        Haptics.success();
        composer.clear();
      },
      onFailure: (failure) {
        // Only reroute onto a socket we actually hold open — otherwise the write
        // is a no-op and we would clear the field having sent nothing.
        if (routeForSend(sendTarget, failure) == SendTarget.terminal && _writeToPty(text)) {
          Haptics.success();
          sendTarget = SendTarget.terminal;
          banner = kReroutedNotice;
          composer.clear();
          return;
        }
        Haptics.error();
        banner = 'Send failed: ${failure.message}';
      },
    );
    sending = false;
    _emit();
  }

  bool _writeToPty(String text) {
    if (!attached || status != MuxStatus.open) return false;
    _mux.sendInput(args.id, terminalPayload(text), projectId: args.projectId);
    return true;
  }

  Future<void> terminate() async {
    final result = args.shellOnly
        ? await _repository.closeShellTerminal(args.id)
        : await _sessions.kill(args.sessionId);
    result.when(
      onSuccess: (_) {
        Haptics.success();
        emit(const TerminalClosedState());
      },
      onFailure: (failure) {
        Haptics.error();
        banner = '${args.shellOnly ? 'Close' : 'Kill'} failed: ${failure.message}';
        _emit();
      },
    );
  }

  Future<void> restore() async {
    restoring = true;
    _emit();
    final result = await _sessions.restore(args.sessionId);
    result.when(
      onSuccess: (_) {
        banner = null;
        notFound = false;
        _reopenTimer?.cancel();
        _reopenTimer = Timer(_restoreDelay, _reopen);
      },
      onFailure: (failure) => banner = 'Restore failed: ${failure.message}',
    );
    restoring = false;
    _emit();
  }

  /// The daemon needs a moment to bring the worktree agent's PTY back before the
  /// re-attach can land.
  void _reopen() {
    if (!attached) return;
    _mux.openTerminal(args.id, projectId: args.projectId);
    final fit = _lastFit;
    if (fit != null) _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
  }

  bool _closed = false;

  @override
  Future<void> close() {
    if (_closed) return super.close();
    _closed = true;
    _reopenTimer?.cancel();
    unawaited(_statusSub?.cancel());
    unawaited(_eventsSub?.cancel());
    if (attached) _mux.closeTerminal(args.id, projectId: args.projectId);
    composer.dispose();
    return super.close();
  }
}
