import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';

part 'usage_state.dart';

class UsageCubit extends Cubit<UsageState> {
  UsageCubit(this._repository) : super(const UsageState());

  final UsageRepository _repository;

  Future<void> load(String bucket) async {
    emit(state.copyWith(status: UsageStatus.loading, bucket: bucket));
    try {
      final rollup = await _repository.rollup(UsageRollupParams(bucket: bucket));
      emit(
        UsageState(
          status: UsageStatus.loaded,
          bucket: bucket,
          buckets: rollup.buckets,
        ),
      );
    } on Failure catch (failure) {
      emit(
        UsageState(
          status: UsageStatus.error,
          bucket: bucket,
          error: failure.apiStatus ?? failure.message,
        ),
      );
    }
  }
}
