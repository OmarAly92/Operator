import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';
import 'package:operator_mobile/feature/usage/data/model/session_context_model.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';
import 'package:operator_mobile/feature/usage/presentation/usage_screen/logic/usage_cubit.dart';

class FakeUsageRepository implements UsageRepository {
  FakeUsageRepository({this.rollupResult, this.error});

  final UsageRollupModel? rollupResult;
  final String? error;

  @override
  Future<UsageRollupModel> rollup(UsageRollupParams params) async {
    if (error != null) {
      throw ServerFailure<Map<String, dynamic>>(error: error!, apiStatus: error);
    }
    return rollupResult ?? const UsageRollupModel();
  }

  @override
  Future<SessionContextModel?> sessionContext(String sessionId) =>
      throw UnimplementedError();
}

void main() {
  group('UsageCubit', () {
    test('emits loaded buckets for the requested grain', () async {
      final cubit = UsageCubit(
        FakeUsageRepository(
          rollupResult: const UsageRollupModel(
            bucket: 'day',
            buckets: [
              UsageBucketModel(start: '2026-09-01', inputTokens: 350, outputTokens: 20),
            ],
          ),
        ),
      );

      await cubit.load('day');

      expect(cubit.state.status, UsageStatus.loaded);
      expect(cubit.state.buckets.single.inputTokens, 350);
      expect(cubit.state.bucket, 'day');
    });

    test('surfaces the error code rather than a generic failure', () async {
      final cubit = UsageCubit(FakeUsageRepository(error: 'INVALID_RANGE'));

      await cubit.load('day');

      expect(cubit.state.status, UsageStatus.error);
      expect(cubit.state.error, 'INVALID_RANGE');
    });
  });
}
