import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';

class _MockMux extends Mock implements MuxClient {}

class _MockRepository extends Mock implements BlocksRepository {}

Map<String, dynamic> _wire(int seq, String kind, {String? text, String? sourceId, String? toolName}) => {
  'seq': seq,
  'sessionId': 's-1',
  'kind': kind,
  'text': ?text,
  'sourceId': ?sourceId,
  'toolName': ?toolName,
};

void main() {
  late _MockMux mux;
  late _MockRepository repository;
  late StreamController<BlockEventEnvelope> events;
  late StreamController<MuxStatus> statuses;
  late StreamController<List<SessionPatch>> patches;

  setUpAll(() => registerFallbackValue(const GetSessionBlocksParams()));

  setUp(() {
    mux = _MockMux();
    repository = _MockRepository();
    events = StreamController<BlockEventEnvelope>.broadcast();
    statuses = StreamController<MuxStatus>.broadcast();
    patches = StreamController<List<SessionPatch>>.broadcast();
    when(() => mux.blockEvents).thenAnswer((_) => events.stream);
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.sessionPatches).thenAnswer((_) => patches.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.subscribeBlocks(any())).thenReturn(null);
    when(() => mux.unsubscribeBlocks(any())).thenReturn(null);
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
  });

  tearDown(() async {
    await events.close();
    await statuses.close();
    await patches.close();
  });

  BlocksCubit build({String? harness = 'claude-code'}) =>
      BlocksCubit(mux, repository, 's-1', harness: harness);

  test('subscribes before it fetches history', () async {
    final order = <String>[];
    when(() => mux.subscribeBlocks(any())).thenAnswer((_) {
      order.add('subscribe');
    });
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      order.add('history');
      return Result.success(const <BlockEventModel>[]);
    });

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    expect(order, ['subscribe', 'history']);
    await cubit.close();
  });

  test('an event that lands before history is not lost or duplicated', () async {
    final gate = Completer<void>();
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      await gate.future;
      return Result.success([
        BlockEventModel.fromJson(_wire(1, 'prompt_submit', text: 'go')),
        BlockEventModel.fromJson(_wire(2, 'stop', text: 'done')),
      ]);
    });

    final cubit = build();
    events.add(BlockEventEnvelope('s-1', _wire(2, 'stop', text: 'done')));
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.map((b) => b.id), ['seq-1', 'seq-2']);
    await cubit.close();
  });

  test('ignores events for another session', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-2', _wire(1, 'stop', text: 'other')));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks, isEmpty);
    await cubit.close();
  });

  test('refetches from the highest seq it holds after a reconnect', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(9, 'stop', text: 'done'))]),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    statuses.add(MuxStatus.closed);
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);

    final captured = verify(() => repository.getSessionBlocks('s-1', captureAny()))
        .captured
        .cast<GetSessionBlocksParams>();
    expect(captured.first.afterSeq, isNull);
    expect(captured.last.afterSeq, 9);
    await cubit.close();
  });

  test('re-subscribes after a reconnect', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    statuses.add(MuxStatus.closed);
    statuses.add(MuxStatus.open);
    await Future<void>.delayed(Duration.zero);

    verify(() => mux.subscribeBlocks('s-1')).called(2);
    await cubit.close();
  });

  test('keeps at most kBlockWindow events, dropping the oldest', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 1; seq <= kBlockWindow + 10; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'line $seq')));
    }
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks, hasLength(kBlockWindow));
    expect(cubit.blocks.first.body, 'line 11');
    expect(cubit.blocks.last.body, 'line ${kBlockWindow + 10}');
    await cubit.close();
  });

  test('pages backwards from the lowest sequence it holds', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(_wire(20, 'stop', text: 'newest')),
      ]),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([
        BlockEventModel.fromJson(_wire(18, 'stop', text: 'older')),
      ]),
    );
    await cubit.loadOlder();

    final captured = verify(() => repository.getSessionBlocks('s-1', captureAny()))
        .captured
        .cast<GetSessionBlocksParams>();
    expect(captured.last.beforeSeq, 20);
    expect(captured.last.afterSeq, isNull, reason: 'the endpoint rejects both cursors');
    expect(cubit.blocks.map((b) => b.body), ['older', 'newest']);
    await cubit.close();
  });

  test('an empty backward page means there is nothing older', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(5, 'stop', text: 'a'))]),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.hasOlder, isTrue);

    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    await cubit.loadOlder();

    expect(cubit.hasOlder, isFalse);
    await cubit.close();
  });

  test('loadOlder does nothing before anything is held', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    await cubit.loadOlder();

    verifyNever(() => repository.getSessionBlocks(any(), any()));
    await cubit.close();
  });

  test('a second loadOlder while one is in flight is ignored', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(9, 'stop', text: 'a'))]),
    );
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    clearInteractions(repository);

    final gate = Completer<void>();
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer((_) async {
      await gate.future;
      return Result.success(const <BlockEventModel>[]);
    });

    final first = cubit.loadOlder();
    final second = cubit.loadOlder();
    gate.complete();
    await first;
    await second;

    verify(() => repository.getSessionBlocks(any(), any())).called(1);
    await cubit.close();
  });

  test('paging older back does not immediately re-trim it away', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 101; seq <= 100 + kBlockWindow; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'line $seq')));
    }
    await Future<void>.delayed(Duration.zero);
    expect(cubit.blocks, hasLength(kBlockWindow));

    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.success([BlockEventModel.fromJson(_wire(100, 'stop', text: 'older'))]),
    );
    await cubit.loadOlder();

    expect(
      cubit.blocks.first.body,
      'older',
      reason: 'a page fetched backwards must not be evicted by the same window that dropped it',
    );
    await cubit.close();
  });

  test('stops offering older pages once the window can hold no more', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 100000; seq < 100000 + kBlockMaxWindow; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'n')));
    }
    await Future<void>.delayed(Duration.zero);

    var page = 0;
    while (cubit.hasOlder && page < 40) {
      final base = 99000 - (page * kBlockPage);
      when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
        (_) async => Result.success([
          for (var k = 0; k < kBlockPage; k++)
            BlockEventModel.fromJson(_wire(base + k, 'stop', text: 'old')),
        ]),
      );
      await cubit.loadOlder();
      page++;
    }

    expect(
      cubit.hasOlder,
      isFalse,
      reason: 'a full window must retire the control, not keep offering a page it would evict',
    );
    expect(cubit.blocks.length, lessThanOrEqualTo(kBlockMaxWindow));
    await cubit.close();
  });

  test('never requests more than the window can still hold', () async {
    when(() => repository.getSessionBlocks(any(), any()))
        .thenAnswer((_) async => Result.success(const <BlockEventModel>[]));
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    for (var seq = 100000; seq < 100000 + kBlockWindow; seq++) {
      events.add(BlockEventEnvelope('s-1', _wire(seq, 'stop', text: 'n')));
    }
    await Future<void>.delayed(Duration.zero);

    var page = 0;
    while (cubit.hasOlder && page < 40) {
      final base = 99000 - (page * kBlockPage);
      when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
        (_) async => Result.success([
          for (var k = 0; k < kBlockPage; k++)
            BlockEventModel.fromJson(_wire(base + k, 'stop', text: 'old')),
        ]),
      );
      await cubit.loadOlder();
      page++;
    }

    final asked = verify(() => repository.getSessionBlocks('s-1', captureAny()))
        .captured
        .cast<GetSessionBlocksParams>()
        .where((p) => p.beforeSeq != null)
        .toList();
    for (final p in asked) {
      expect(p.limit, isNotNull);
      expect(p.limit!, lessThanOrEqualTo(kBlockPage));
      expect(p.limit!, greaterThan(0));
    }
    await cubit.close();
  });

  test('an exited session leaves no block spinning', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'prompt_submit', text: 'go')));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.blocks.single.status, BlockStatus.running);

    patches.add(const [
      SessionPatch(
        id: 's-1',
        status: 'terminated',
        activity: 'exited',
        attentionLevel: 'none',
        lastActivityAt: '2026-08-27T10:00:00Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.status, BlockStatus.failed);
    expect(cubit.blocks.single.body, isNotEmpty);
    await cubit.close();
  });

  test('a patch for another session does not strand this one', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'prompt_submit', text: 'go')));
    patches.add(const [
      SessionPatch(
        id: 's-2',
        status: 'terminated',
        activity: 'exited',
        attentionLevel: 'none',
        lastActivityAt: '2026-08-27T10:00:00Z',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.status, BlockStatus.running);
    await cubit.close();
  });

  test('surfaces a history failure without discarding live events', () async {
    when(() => repository.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'boom', message: 'boom')),
    );

    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.error, isNotNull);

    events.add(BlockEventEnvelope('s-1', _wire(1, 'stop', text: 'live')));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.blocks.single.body, 'live');
    await cubit.close();
  });

  test('an uncovered harness never touches the socket', () async {
    final cubit = build(harness: 'aider');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.supported, isFalse);
    expect(cubit.state, isA<BlocksUnsupportedState>());
    verifyNever(() => mux.subscribeBlocks(any()));
    verifyNever(() => repository.getSessionBlocks(any(), any()));
    await cubit.close();
  });

  test('unsubscribes on close', () async {
    final cubit = build();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();

    verify(() => mux.unsubscribeBlocks('s-1')).called(1);
  });
}
