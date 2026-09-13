import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';

part 'blocks_state.dart';

const int kBlockWindow = 400;

const int kBlockPage = 100;

const int kBlockMaxWindow = 1200;

const String kSessionEndedReason = 'Session ended before this finished';

class BlocksCubit extends Cubit<BlocksState> {
  BlocksCubit(
    this._mux,
    this._repository,
    this.sessionId, {
    required SessionsCubit sessions,
    this.harness,
  }) : supported = BlockHarnesses.covers(harness),
       super(const BlocksInitialState()) {
    if (!supported) {
      emit(BlocksUnsupportedState(harness));
      return;
    }
    _eventsSub = _mux.blockEvents
        .where((event) => event.sessionId == sessionId)
        .listen(_onLive);
    _statusSub = _mux.status.listen(_onStatus);
    _sessionSub = sessions.watchSession(sessionId).listen(_onSession);
    _mux.subscribeBlocks(sessionId);
    unawaited(refresh());
  }

  final MuxClient _mux;
  final BlocksRepository _repository;
  final String sessionId;
  final String? harness;
  final bool supported;

  List<SessionBlock> blocks = const [];
  bool loading = false;
  bool active = false;
  bool loadingOlder = false;
  bool hasOlder = false;
  String? error;

  final SplayTreeMap<int, BlockEventModel> _events =
      SplayTreeMap<int, BlockEventModel>();
  bool _ended = false;
  int _revision = 0;
  int _capacity = kBlockWindow;

  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<SessionModel>? _sessionSub;

  int? get _highestSeq => _events.isEmpty ? null : _events.lastKey();

  int? get _lowestSeq => _events.isEmpty ? null : _events.firstKey();

  Future<void> refresh() async {
    if (isClosed) return;
    loading = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(afterSeq: _highestSeq),
    );
    if (isClosed) return;
    result.when(
      onSuccess: (records) {
        error = null;
        for (final record in records) {
          _merge(record);
        }
      },
      onFailure: (failure) => error = failure.message.isEmpty
          ? 'Could not load this session\'s blocks'
          : failure.message,
    );
    loading = false;
    _rebuild();
  }

  Future<void> loadOlder() async {
    if (isClosed || loadingOlder || !hasOlder) return;
    final before = _lowestSeq;
    if (before == null) return;

    final headroom = kBlockMaxWindow - _capacity;
    if (headroom <= 0) {
      hasOlder = false;
      _emit();
      return;
    }

    loadingOlder = true;
    _emit();
    final limit = min(kBlockPage, headroom);
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(beforeSeq: before, limit: limit),
    );
    if (isClosed) return;
    result.when(
      onSuccess: (records) {
        error = null;
        if (records.isEmpty) {
          hasOlder = false;
        } else {
          _capacity = min(kBlockMaxWindow, _capacity + records.length);
          for (final record in records) {
            _merge(record);
          }
          hasOlder = records.length == limit && _capacity < kBlockMaxWindow;
        }
      },
      onFailure: (failure) => error = failure.message.isEmpty
          ? 'Could not load older blocks'
          : failure.message,
    );
    loadingOlder = false;
    _rebuild();
  }

  void _onLive(BlockEventEnvelope envelope) {
    _merge(BlockEventModel.fromJson(envelope.block));
    _rebuild();
  }

  void _onStatus(MuxStatus status) {
    if (status != MuxStatus.open) return;
    _mux.subscribeBlocks(sessionId);
    unawaited(refresh());
  }

  void _onSession(SessionModel session) {
    if (isClosed) return;
    final ended = session.isTerminated == true || session.activity == 'exited';
    final busy = !ended && session.activity == 'active';
    if (ended != _ended || busy != active) {
      _ended = ended;
      active = busy;
      _rebuild();
    }
  }

  void _merge(BlockEventModel record) {
    final seq = record.seq;
    if (seq == null) return;
    _events[seq] = record;
    while (_events.length > _capacity) {
      _events.remove(_events.firstKey());
      hasOlder = _capacity < kBlockMaxWindow;
    }
  }

  void _rebuild() {
    final assembled = assembleBlocks(_events.values);
    blocks = _ended
        ? resolveStranded(assembled, kSessionEndedReason)
        : assembled;
    _emit();
  }

  void _emit() {
    if (isClosed) return;
    emit(BlocksReadyState(++_revision));
  }

  @override
  Future<void> close() {
    unawaited(_eventsSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_sessionSub?.cancel());
    if (supported) _mux.unsubscribeBlocks(sessionId);
    return super.close();
  }
}
