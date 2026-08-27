import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';

class _MockDataSource extends Mock implements BlocksRemoteDataSource {}

class _OnlineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => true;
}

class _OfflineNetwork implements NetworkStatus {
  @override
  Future<bool> get isConnected async => false;
}

void main() {
  setUpAll(() => registerFallbackValue(const GetSessionBlocksParams()));

  test('the endpoint encodes the session id', () {
    expect(EndPoints.sessionBlocks('a b/c'), '/api/v1/sessions/a%20b%2Fc/blocks');
  });

  test('returns the parsed log', () async {
    final source = _MockDataSource();
    when(() => source.getSessionBlocks(any(), any())).thenAnswer(
      (_) async => const [BlockEventModel(seq: 1, kind: 'stop')],
    );
    final repository = BlocksRepositoryImp(source, _OnlineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4));

    expect(result.isSuccess, isTrue);
    expect(result.getOrDefault(const []).single.seq, 1);
    verify(() => source.getSessionBlocks('s-1', const GetSessionBlocksParams(afterSeq: 4))).called(1);
  });

  test('fails without a network instead of calling the daemon', () async {
    final source = _MockDataSource();
    final repository = BlocksRepositoryImp(source, _OfflineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
    verifyNever(() => source.getSessionBlocks(any(), any()));
  });

  test('surfaces a data-source failure as a Result failure', () async {
    final source = _MockDataSource();
    when(() => source.getSessionBlocks(any(), any())).thenThrow(
      ServerFailure(error: 'boom', message: 'boom', statusCode: 500),
    );
    final repository = BlocksRepositoryImp(source, _OnlineNetwork());

    final result = await repository.getSessionBlocks('s-1', const GetSessionBlocksParams());

    expect(result.isFailure, isTrue);
  });
}
