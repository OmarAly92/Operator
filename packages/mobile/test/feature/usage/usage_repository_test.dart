import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/usage/data/data_source/usage_remote_data_source.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';

class FakeUsageRemoteDataSource implements UsageRemoteDataSource {
  FakeUsageRemoteDataSource({required this.sessionJson});

  final Map<String, dynamic> sessionJson;

  @override
  Future<GlobalResponse<UsageRollupModel>> rollup(UsageRollupParams params) {
    throw UnimplementedError();
  }

  @override
  Future<GlobalResponse<Map<String, dynamic>>> sessionContext(
    String sessionId,
  ) async => GlobalResponse(data: sessionJson);
}

void main() {
  test('returns null context when the daemon omits it', () async {
    final repo = UsageRepository(
      FakeUsageRemoteDataSource(sessionJson: const {'sessionId': 'scratch-1'}),
    );

    expect(await repo.sessionContext('scratch-1'), isNull);
  });

  test('parses the context when present', () async {
    final repo = UsageRepository(
      FakeUsageRemoteDataSource(
        sessionJson: const {
          'sessionId': 'scratch-1',
          'context': {'harness': 'claude-code', 'used': 64880, 'window': 0},
        },
      ),
    );

    final ctx = await repo.sessionContext('scratch-1');

    expect(ctx!.used, 64880);
    expect(ctx.hasWindow, isFalse);
  });
}
