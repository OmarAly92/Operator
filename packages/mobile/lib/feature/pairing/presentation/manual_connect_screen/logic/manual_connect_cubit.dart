import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

part 'manual_connect_state.dart';

class ManualConnectCubit extends Cubit<ManualConnectState> {
  ManualConnectCubit(this._repository, ServerConfigStore serverConfigStore)
    : hostController = TextEditingController(text: serverConfigStore.current?.host ?? ''),
      portController = TextEditingController(text: serverConfigStore.current?.httpPort ?? '3011'),
      passwordController = TextEditingController(text: serverConfigStore.current?.password ?? ''),
      _secure = serverConfigStore.current?.secure ?? false,
      super(const ManualConnectInitialState());

  final PairingRepository _repository;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController passwordController;
  bool _secure;

  bool get secure => _secure;

  void setSecure(bool value) {
    _secure = value;
    emit(SecureToggledState(value));
  }

  Future<void> connect(TargetPlatform platform) async {
    emit(const ConnectLoadingState());
    final target = ServerConfig(
      host: hostController.text.trim(),
      httpPort: portController.text.trim(),
      secure: _secure,
      password: passwordController.text,
    );
    final result = await _repository.verifyAndConnect(target);
    result.when(
      onSuccess: (_) => emit(const ConnectSuccessState()),
      onFailure: (failure) => emit(
        ConnectFailureState(
          describeConnectionFailure(
            classifyConnectionFailure(failure.statusCode),
            host: target.host,
            port: target.httpPort,
            platform: platform,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> close() {
    hostController.dispose();
    portController.dispose();
    passwordController.dispose();
    return super.close();
  }
}
