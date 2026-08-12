import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';

abstract class PairingRepository {
  FutureResult<bool> verifyAndConnect(ServerConfig target);
}

class PairingRepositoryImp implements PairingRepository {
  PairingRepositoryImp(this._remoteDataSource, this._serverConfigStore);

  final PairingRemoteDataSource _remoteDataSource;
  final ServerConfigStore _serverConfigStore;

  @override
  FutureResult<bool> verifyAndConnect(ServerConfig target) async {
    try {
      await _remoteDataSource.ping(target);
      await _serverConfigStore.save(target);
      return Result.success(true);
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
