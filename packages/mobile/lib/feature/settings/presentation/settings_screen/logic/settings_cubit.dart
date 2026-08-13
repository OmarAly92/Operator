import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/logic/disconnect.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository, this._store) : super(const SettingsInitialState());

  final SessionsRepository _repository;
  final ServerConfigStore _store;

  Future<void> testConnection() async {
    emit(const PingLoadingState());
    final result = await _repository.getBoard();
    result.when(
      onSuccess: (response) => emit(PingSuccessState(response.data?.sessions.length ?? 0)),
      onFailure: (failure) => emit(PingFailureState(failure)),
    );
  }

  Future<void> forget() async {
    await forgetServer(_store);
    emit(const ForgetSuccessState());
  }
}
