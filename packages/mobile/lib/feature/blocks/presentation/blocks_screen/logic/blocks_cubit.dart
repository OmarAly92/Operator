import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
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
  BlocksCubit(this._mux, this._repository, this.sessionId, {this.harness})
    : supported = BlockHarnesses.covers(harness),
      super(const BlocksInitialState()) {
    if (!supported) {
      emit(BlocksUnsupportedState(harness));
      return;
    }
    _eventsSub = _mux.blockEvents.where((event) => event.sessionId == sessionId).listen(_onLive);
    _statusSub = _mux.status.listen(_onStatus);
    _patchesSub = _mux.sessionPatches.listen(_onPatches);
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
  bool loadingOlder = false;
  bool hasOlder = true;
  String? error;

  final SplayTreeMap<int, BlockEventModel> _events = SplayTreeMap<int, BlockEventModel>();
  bool _ended = false;
  int _revision = 0;
  int _capacity = kBlockWindow;

  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<List<SessionPatch>>? _patchesSub;

  int? get _highestSeq => _events.isEmpty ? null : _events.lastKey();

  int? get _lowestSeq => _events.isEmpty ? null : _events.firstKey();

  Future<void> refresh() async {
    loading = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(afterSeq: _highestSeq),
    );
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
    if (loadingOlder || !hasOlder) return;
    final before = _lowestSeq;
    if (before == null) return;

    loadingOlder = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(beforeSeq: before, limit: kBlockPage),
    );
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

  void _onPatches(List<SessionPatch> patches) {
    for (final patch in patches) {
      if (patch.id != sessionId) continue;
      final ended = patch.activity == 'exited' || patch.status == 'terminated';
      if (ended != _ended) {
        _ended = ended;
        _rebuild();
      }
      return;
    }
  }

  void _merge(BlockEventModel record) {
    final seq = record.seq;
    if (seq == null) return;
    _events[seq] = record;
    while (_events.length > _capacity) {
      _events.remove(_events.firstKey());
    }
  }

  void _rebuild() {
    final assembled = assembleBlocks(_events.values);
    blocks = _ended ? resolveStranded(assembled, kSessionEndedReason) : assembled;
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
    unawaited(_patchesSub?.cancel());
    if (supported) _mux.unsubscribeBlocks(sessionId);
    return super.close();
  }
}
