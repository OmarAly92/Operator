import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/logic/pairing_payload.dart';

part 'pairing_scan_state.dart';

class PairingScanCubit extends Cubit<PairingScanState> {
  PairingScanCubit(this._repository, this._serverConfigStore, {required this.fromOnboarding})
    : super(const PairingScanInitialState());

  final PairingRepository _repository;
  final ServerConfigStore _serverConfigStore;
  final bool fromOnboarding;

  bool _scanned = false;

  Future<void> onScan(String raw, TargetPlatform platform) async {
    if (_scanned || state is VerifyLoadingState) return;

    final parsed = parsePairingPayload(raw);
    if (parsed == null) {
      emit(VerifyFailureState(describeConnectionFailure(ConnectionFailure.notOprQr, host: '', port: '', platform: platform)));
      return;
    }

    _scanned = true;
    final current = _serverConfigStore.current;
    final target = ServerConfig(
      host: parsed.host,
      httpPort: parsed.port,
      secure: current?.secure ?? false,
      password: parsed.password.isNotEmpty ? parsed.password : (current?.password ?? ''),
    );

    emit(const VerifyLoadingState());
    final result = await _repository.verifyAndConnect(target);
    result.when(
      onSuccess: (_) => emit(const VerifySuccessState()),
      onFailure: (failure) {
        _scanned = false;
        emit(
          VerifyFailureState(
            describeConnectionFailure(
              classifyConnectionFailure(failure.statusCode),
              host: target.host,
              port: target.httpPort,
              platform: platform,
            ),
          ),
        );
      },
    );
  }
}
