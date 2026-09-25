import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

abstract class PairingRepository {
  FutureResult<DesktopModel> verifyAndConnect(ServerConfig target);
}

class PairingRepositoryImp implements PairingRepository {
  PairingRepositoryImp(this._remote, this._desktops, this._store);

  final PairingRemoteDataSource _remote;
  final DesktopsRepository _desktops;
  final ServerConfigStore _store;

  @override
  FutureResult<DesktopModel> verifyAndConnect(ServerConfig target) async {
    try {
      final identity = await _remote.identify(target);
      final name = identity.name?.trim();
      final saved = await _desktops.save(
        SaveDesktopParams(
          name: name == null || name.isEmpty ? '${target.host}:${target.httpPort}' : name,
          host: target.host,
          port: target.httpPort,
          secure: target.secure,
          password: target.password,
        ),
      );
      final desktop = saved.valueOrNull;
      if (desktop != null) _store.set(desktop.toServerConfig(target.password));
      return saved;
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
