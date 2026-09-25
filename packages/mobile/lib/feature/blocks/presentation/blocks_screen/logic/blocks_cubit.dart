import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/replica/replica_limits.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_tasks_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/stop_session_task_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/background_tasks.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/subagents.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';

part 'blocks_state.dart';

const int kBlockWindow = 400;

const int kBlockPage = 100;

const int kBlockMaxWindow = 1200;

const String kSessionEndedReason = 'Session ended before this finished';

class BlocksScope extends Equatable {
  const BlocksScope({required this.sessionId, this.harness, this.agentId});

  final String sessionId;
  final String? harness;
  final String? agentId;

  @override
  List<Object?> get props => [sessionId, harness, agentId];
}

class BlocksCubit extends Cubit<BlocksState> {
  BlocksCubit(this._mux, this._repository, this.scope, {required this._tasks})
    : supported = BlockHarnesses.covers(scope.harness),
      super(const BlocksInitialState()) {
    if (!supported) {
      emit(BlocksUnsupportedState(harness));
      return;
    }
    _eventsSub = _mux.blockEvents.where((event) => event.sessionId == sessionId).listen(_onLive);
    _statusSub = _mux.status.listen(_onStatus);
    _patchesSub = _mux.sessionPatches.listen(_onPatches);
    _mux.subscribeBlocks(sessionId);
    loading = true;
    unawaited(_start());
    unawaited(_seedTasks());
  }

  final MuxClient _mux;
  final BlocksRepository _repository;
  final BackgroundTasksRepository _tasks;
  final BlocksScope scope;
  String get sessionId => scope.sessionId;
  String? get agentId => scope.agentId;
  String? get harness => scope.harness;
  final bool supported;

  List<SessionBlock> blocks = const [];
  bool loading = false;
  bool active = false;
  bool loadingOlder = false;
  bool hasOlder = false;
  String? error;

  final SplayTreeMap<int, BlockEventModel> _events = SplayTreeMap<int, BlockEventModel>();
  bool _ended = false;
  bool _blocked = false;
  int _answeredThroughSeq = 0;
  int _revision = 0;
  int _capacity = kBlockWindow;
  bool _historyLoaded = false;
  int? _cachedThrough;

  StreamSubscription<BlockEventEnvelope>? _eventsSub;
  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<List<SessionPatch>>? _patchesSub;

  int _taskSeq = 0;
  int? _lowestTaskSeq;

  int? get _highestSeq {
    final highest = _events.isEmpty ? _taskSeq : max(_events.lastKey()!, _taskSeq);
    return highest == 0 ? null : highest;
  }

  int? get _lowestSeq {
    final kept = _events.isEmpty ? null : _events.firstKey();
    final task = _lowestTaskSeq;
    if (kept == null || task == null) return kept ?? task;
    return min(kept, task);
  }

  Future<void> _start() async {
    if (agentId == null) await _seedFromCache();
    if (isClosed) return;
    await refresh();
  }

  Future<void> _seedFromCache() async {
    final cached = await _repository.cachedHistory(sessionId);
    if (isClosed || cached.isEmpty) return;
    var through = 0;
    for (final record in cached) {
      final seq = record.seq;
      if (seq == null) continue;
      through = max(through, seq);
      if (_events.containsKey(seq)) continue;
      _merge(record);
    }
    _cachedThrough = through == 0 ? null : through;
    if (cached.length >= ReplicaLimits.blockEventsPerSession) hasOlder = true;
    _rebuild();
  }

  Future<void> refresh() async {
    loading = true;
    _emit();
    final result = await _repository.getSessionBlocks(
      sessionId,
      GetSessionBlocksParams(afterSeq: _historyLoaded ? _highestSeq : _cachedThrough, agentId: agentId),
    );
    result.when(
      onSuccess: (records) {
        error = null;
        _historyLoaded = true;
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
      GetSessionBlocksParams(beforeSeq: before, limit: limit, agentId: agentId),
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
    final record = BlockEventModel.fromJson(envelope.block);
    final scopeId = record.agentId ?? '';
    if (agentId == null && scopeId.isEmpty) unawaited(_repository.rememberLive(sessionId, envelope.block));
    if (record.kind == 'task_update') {
      if (agentId == null) _absorbTask(record);
      if (scopeId == (agentId ?? '')) _merge(record);
      return;
    }
    if (scopeId == (agentId ?? '')) {
      if (agentId == null && record.kind == 'agent_stop' && (record.sourceId ?? '').isNotEmpty) {
        _summarise(record.sourceId!, record);
      }
      _merge(record);
      _rebuild();
      return;
    }
    if (agentId == null && scopeId.isNotEmpty) _summarise(scopeId, record);
  }

  final Map<String, SubagentSummary> _summaries = {};
  Map<String, SubagentSummary> get subagentSummaries => Map.unmodifiable(_summaries);

  void _summarise(String scopeId, BlockEventModel record) {
    final current = _summaries[scopeId] ?? SubagentSummary(agentId: scopeId);
    _summaries[scopeId] = current.absorb(
      prompt: record.kind == 'prompt_submit' ? record.text : null,
      at: record.createdAt,
      stopped: record.kind == 'agent_stop',
    );
    _emit();
  }

  void _onStatus(MuxStatus status) {
    if (status != MuxStatus.open) return;
    _mux.subscribeBlocks(sessionId);
    unawaited(refresh());
    unawaited(_seedTasks());
  }

  final Map<String, BackgroundTaskModel> _taskFeed = {};
  Map<String, BackgroundTaskModel> get taskFeed => UnmodifiableMapView(_taskFeed);
  bool _taskFeedMissing = false;
  bool _seeding = false;
  bool _reseed = false;

  Future<void> reseedTasks() => _seedTasks();

  Future<void> _seedTasks() async {
    final tasks = _tasks;
    if (agentId != null || !supported || _taskFeedMissing) return;
    if (_seeding) {
      _reseed = true;
      return;
    }
    _seeding = true;
    do {
      _reseed = false;
      final result = await tasks.getTasks(GetSessionTasksParams(sessionId: sessionId));
      if (isClosed) return;
      result.when(
        onSuccess: (response) {
          for (final task in response.data ?? const <BackgroundTaskModel>[]) {
            _foldTask(task);
          }
          _emit();
        },
        onFailure: (failure) {
          final status = failure.statusCode;
          if (status == StatusCode.notFound || status == StatusCode.notImplemented) _taskFeedMissing = true;
        },
      );
    } while (_reseed && !_taskFeedMissing);
    _seeding = false;
  }

  void _absorbTask(BlockEventModel record) {
    final update = BackgroundTaskModel.fromEvent(record);
    if (update == null) return;
    final merged = _foldTask(update);
    if (merged.status == 'running' && merged.canStop == null) unawaited(_seedTasks());
    _emit();
  }

  BackgroundTaskModel _foldTask(BackgroundTaskModel update) {
    final id = update.taskId;
    if (id == null || id.isEmpty) return update;
    return _taskFeed[id] = mergeBackgroundTask(_taskFeed[id], update);
  }

  Future<Failure?> stopTask(String taskId) async {
    final result = await _tasks.stopTask(StopSessionTaskParams(sessionId: sessionId, taskId: taskId));
    Failure? failure;
    result.when(
      onSuccess: (response) {
        final task = response.data?.task;
        if (task != null && !isClosed) {
          _foldTask(task);
          _emit();
        }
      },
      onFailure: (error) => failure = error,
    );
    return failure;
  }

  void _onPatches(List<SessionPatch> patches) {
    for (final patch in patches) {
      if (patch.id != sessionId) continue;
      final ended = patch.activity == 'exited' || patch.status == 'terminated';
      final busy = patch.activity == 'active';
      final blocked = patch.activity == 'blocked';
      var changed = ended != _ended || busy != active;
      if (_blocked && !blocked) {
        _answeredThroughSeq = _highestSeq ?? 0;
        changed = true;
      }
      _blocked = blocked;
      if (changed) {
        _ended = ended;
        active = busy;
        _rebuild();
      }
      return;
    }
  }

  void _merge(BlockEventModel record) {
    final seq = record.seq;
    if (seq == null) return;
    if (record.kind == 'task_update') {
      _taskSeq = max(_taskSeq, seq);
      _lowestTaskSeq = min(_lowestTaskSeq ?? seq, seq);
      return;
    }
    _events[seq] = record;
    while (_events.length > _capacity) {
      final evicted = _events.firstKey()!;
      _events.remove(evicted);
      if ((_lowestTaskSeq ?? evicted) < evicted) _lowestTaskSeq = null;
      hasOlder = _capacity < kBlockMaxWindow;
    }
  }

  void _rebuild() {
    final assembled = resolveAnswered(assembleBlocks(_events.values), _answeredThroughSeq);
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
