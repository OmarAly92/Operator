import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';

abstract class DesktopsRepository {
  Stream<List<DesktopModel>> watchDesktops();
  FutureResult<DesktopModel?> getActive();
  FutureResult<DesktopModel> save(SaveDesktopParams params);
  FutureResult<void> activate(String id);
  FutureResult<void> deactivate();
  FutureResult<void> rename(RenameDesktopParams params);
  FutureResult<void> remove(String id);
  FutureResult<String?> passwordFor(String id);
}

class DesktopsRepositoryImp implements DesktopsRepository {
  DesktopsRepositoryImp(this._local);

  final DesktopsLocalDataSource _local;

  @override
  Stream<List<DesktopModel>> watchDesktops() => _local.watchAll();

  @override
  FutureResult<DesktopModel?> getActive() => _guard(_local.getActive);

  @override
  FutureResult<DesktopModel> save(SaveDesktopParams params) => _guard(() => _local.save(params));

  @override
  FutureResult<void> activate(String id) => _guard(() => _local.activate(id));

  @override
  FutureResult<void> deactivate() => _guard(_local.deactivate);

  @override
  FutureResult<void> rename(RenameDesktopParams params) => _guard(() => _local.rename(params));

  @override
  FutureResult<void> remove(String id) => _guard(() => _local.remove(id));

  @override
  FutureResult<String?> passwordFor(String id) => _guard(() => _local.passwordFor(id));

  FutureResult<T> _guard<T>(Future<T> Function() run) async {
    try {
      return Result.success(await run());
    } on Failure catch (error) {
      return Result.failure(error);
    }
  }
}
