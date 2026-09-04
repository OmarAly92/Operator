import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/events/conversation_event_bus.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/logic/conversation_blocks.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';

class ConversationBlocksCubit extends Cubit<ConversationBlocksState> {
  ConversationBlocksCubit(
    this._repository,
    this._eventBus,
    this.sessionId, {
    this._refreshDebounce = const Duration(milliseconds: 120),
  }) : super(const ConversationBlocksInitialState()) {
    unawaited(_initialFetch());
  }

  final ChatRepository _repository;

  ChatRepository get repository => _repository;
  final ConversationEventBus _eventBus;
  final String sessionId;
  final Duration _refreshDebounce;

  ConversationSnapshotModel? get snapshot => _snapshot;

  StreamSubscription<ConversationEventModel>? _eventSub;
  StreamSubscription<void>? _reconnectSub;
  ConversationSnapshotModel? _snapshot;
  int _revision = 0;
  bool _disposed = false;

  Timer? _refreshTimer;
  int _fetchGeneration = 0;

  Future<void> _initialFetch() async {
    if (_disposed) return;
    _emitReady(
      const ConversationBlocksReadyState(
        revision: 0,
        blocks: [],
        isLoading: true,
      ),
    );
    await _fetch();
  }

  Future<void> _fetch({int? beforeSequence}) async {
    final generation = ++_fetchGeneration;
    final result = await _repository.getConversationPage(
      sessionId,
      beforeSequence: beforeSequence,
    );
    if (_disposed) return;
    // A burst of events can leave several page requests in flight. Applying a
    // response that is no longer the newest would move the timeline backwards.
    if (beforeSequence == null && generation != _fetchGeneration) return;
    result.when(
      onSuccess: (response) {
        final data = response.data;
        if (data == null) {
          _applyEmptyResponse(beforeSequence: beforeSequence);
          return;
        }
        _applySnapshot(data, beforeSequence: beforeSequence);
      },
      onFailure: (failure) =>
          _applyFailure(failure, beforeSequence: beforeSequence),
    );
  }

  void _applySnapshot(
    ConversationSnapshotModel snapshot, {
    int? beforeSequence,
  }) {
    if (_disposed) return;
    if (beforeSequence == null) {
      _snapshot = snapshot;
      _emitReady(
        ConversationBlocksReadyState(
          revision: ++_revision,
          blocks: blocksFromConversation(snapshot),
          isLoading: false,
          hasOlder: snapshot.hasMoreBefore,
        ),
      );
      if (_eventSub == null) _subscribe();
    } else {
      _mergeOlderPage(snapshot);
    }
  }

  void _mergeOlderPage(ConversationSnapshotModel older) {
    if (_disposed) return;
    final current = state;
    if (current is! ConversationBlocksReadyState) return;
    final live = _snapshot;
    if (live == null) {
      _emitReady(
        current.copyWith(
          revision: ++_revision,
          isLoadingOlder: false,
          hasOlder: older.hasMoreBefore,
          clearError: true,
        ),
      );
      return;
    }
    final itemsById = <String, ConversationItemModel>{
      for (final item in older.items)
        if (item.id != null) item.id!: item,
      for (final item in live.items)
        if (item.id != null) item.id!: item,
    };
    final turnsById = <String, ConversationTurnModel>{
      for (final turn in older.turns)
        if (turn.id != null) turn.id!: turn,
      for (final turn in live.turns)
        if (turn.id != null) turn.id!: turn,
    };
    final mergedItems = itemsById.values.toList()
      ..sort(
        (left, right) => (left.sequence ?? 0).compareTo(right.sequence ?? 0),
      );
    final mergedTurns = turnsById.values.toList()
      ..sort(
        (left, right) =>
            (left.requestedAt ?? '').compareTo(right.requestedAt ?? ''),
      );
    final merged = live.copyWith(
      items: mergedItems,
      turns: mergedTurns,
      hasMoreBefore: older.hasMoreBefore,
      oldestSequence: older.oldestSequence,
    );
    _snapshot = merged;
    _emitReady(
      current.copyWith(
        revision: ++_revision,
        blocks: blocksFromConversation(merged),
        isLoadingOlder: false,
        hasOlder: older.hasMoreBefore,
        clearError: true,
        clearUnavailable: true,
      ),
    );
  }

  void _applyEmptyResponse({required int? beforeSequence}) {
    if (_disposed) return;
    final current = state;
    if (current is! ConversationBlocksReadyState) {
      _emitReady(
        ConversationBlocksReadyState(
          revision: ++_revision,
          blocks: const [],
          isLoading: false,
        ),
      );
      return;
    }
    if (beforeSequence != null) {
      _emitReady(
        current.copyWith(
          revision: ++_revision,
          isLoadingOlder: false,
        ),
      );
      return;
    }
    _emitReady(
      current.copyWith(
        revision: ++_revision,
        isLoading: false,
      ),
    );
  }

  void _applyFailure(Failure failure, {required int? beforeSequence}) {
    final code = conversationErrorCode(failure);
    final message = conversationActionError(failure);
    if (code != null && kPermanentConversationCodes.contains(code)) {
      emit(ConversationBlocksUnsupportedState((code: code, message: message)));
      return;
    }
    final current = state;
    if (current is! ConversationBlocksReadyState) {
      _emitReady(
        ConversationBlocksReadyState(
          revision: ++_revision,
          blocks: const [],
          isLoading: false,
          error: message,
        ),
      );
      return;
    }
    if (beforeSequence != null) {
      _emitReady(
        current.copyWith(
          revision: ++_revision,
          isLoadingOlder: false,
          error: message,
        ),
      );
      return;
    }
    _emitReady(
      current.copyWith(
        revision: ++_revision,
        isLoading: false,
        error: message,
      ),
    );
  }

  void _subscribe() {
    if (_disposed) return;
    _eventBus.connect();
    _eventSub ??= _eventBus.eventsFor(sessionId).listen(_onEvent);
    // Events emitted while the stream was down were never delivered; refetch
    // once on every (re)connection to cover the gap.
    _reconnectSub ??= _eventBus.reconnects.listen((_) => unawaited(_fetch()));
  }

  void _onEvent(ConversationEventModel _) {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () => unawaited(_fetch()));
  }

  Future<void> onResumed() async {
    if (_disposed) return;
    _eventBus.onResumed();
    await _fetch();
  }

  Future<void> loadOlder() async {
    final current = state;
    if (current is! ConversationBlocksReadyState) return;
    if (current.isLoadingOlder || !current.hasOlder) return;
    final live = _snapshot;
    if (live == null) return;
    final oldest = live.oldestSequence;
    _emitReady(
      current.copyWith(revision: ++_revision, isLoadingOlder: true),
    );
    await _fetch(beforeSequence: oldest);
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final current = state;
    if (current is ConversationBlocksReadyState) {
      _emitReady(
        current.copyWith(
          revision: ++_revision,
          isLoading: true,
          clearError: true,
        ),
      );
    } else {
      _emitReady(
        ConversationBlocksReadyState(
          revision: ++_revision,
          blocks: const [],
          isLoading: true,
        ),
      );
    }
    await _fetch();
  }

  void _emitReady(ConversationBlocksReadyState next) {
    if (_disposed) return;
    emit(next);
  }

  @override
  Future<void> close() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    unawaited(_reconnectSub?.cancel());
    _reconnectSub = null;
    return super.close();
  }
}
