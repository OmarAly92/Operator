import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/rollback_turn_params.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockRemote extends Mock implements ChatRemoteDataSource {}

class _MockEvents extends Mock implements ChatEventDataSource {}

class _MockNetwork extends Mock implements NetworkStatus {}

class _FakeCancelToken extends Fake implements CancelToken {}

class _FakeRollbackParams extends Fake implements RollbackTurnParams {}

void main() {
  late _MockRemote remote;
  late _MockEvents events;
  late _MockNetwork network;
  late ChatRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(_FakeRollbackParams());
  });

  setUp(() {
    remote = _MockRemote();
    events = _MockEvents();
    network = _MockNetwork();
    repository = ChatRepositoryImp(remote, events, network);
    when(() => network.isConnected).thenAnswer((_) async => true);
  });

  test('returns the conversation page when the daemon answers', () async {
    when(
      () => remote.getConversationPage('w-1', beforeSequence: null),
    ).thenAnswer(
      (_) async => const GlobalResponse(
        data: ConversationSnapshotModel(conversationId: 'c-1'),
      ),
    );

    final result = await repository.getConversationPage('w-1');
    expect(result.isSuccess, isTrue);
    result.when(
      onSuccess: (response) => expect(response.data!.conversationId, 'c-1'),
      onFailure: (_) => fail('expected success'),
    );
  });

  test('surfaces the daemon failure rather than throwing', () async {
    when(
      () => remote.getConversationPage('w-1', beforeSequence: null),
    ).thenThrow(
      ServerFailure(
        error: 'nope',
        message: 'Conversation unavailable',
        apiStatus: 'CHAT_RESUME_FAILED',
      ),
    );

    final result = await repository.getConversationPage('w-1');
    expect(result.isFailure, isTrue);
    result.when(
      onSuccess: (_) => fail('expected failure'),
      onFailure: (failure) => expect(failure.apiStatus, 'CHAT_RESUME_FAILED'),
    );
  });

  test('short-circuits every request while offline', () async {
    when(() => network.isConnected).thenAnswer((_) async => false);

    expect((await repository.getConversationPage('w-1')).isFailure, isTrue);
    expect((await repository.interrupt('w-1')).isFailure, isTrue);
    expect(
      (await repository.rollbackTurn(
        'w-1',
        const RollbackTurnParams(turnId: 't-1'),
      )).isFailure,
      isTrue,
    );
    verifyNever(
      () => remote.getConversationPage(
        any(),
        beforeSequence: any(named: 'beforeSequence'),
      ),
    );
    verifyNever(() => remote.interrupt(any()));
  });

  test('reports a void action as a success flag', () async {
    when(() => remote.interrupt('w-1')).thenAnswer((_) async {});
    expect((await repository.interrupt('w-1')).getOrDefault(false), isTrue);
  });

  test('passes the event stream through without a network gate', () async {
    when(
      () => events.stream(after: 3, cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) => Stream.value(const ConversationEventModel(seq: 4)));
    when(() => network.isConnected).thenAnswer((_) async => false);

    final received = await repository
        .events(after: 3, cancelToken: CancelToken())
        .toList();
    expect(received.single.seq, 4);
    verifyNever(() => network.isConnected);
  });
}
