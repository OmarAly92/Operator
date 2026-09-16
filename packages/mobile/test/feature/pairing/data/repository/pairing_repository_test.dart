import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockStore extends Mock implements ServerConfigStore {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');
const _saved = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);

void main() {
  late _MockRemote remote;
  late _MockDesktops desktops;
  late _MockStore store;
  late PairingRepositoryImp repository;

  setUpAll(() {
    registerFallbackValue(_target);
    registerFallbackValue(const SaveDesktopParams(name: '', host: '', port: '', secure: false, password: ''));
  });

  setUp(() {
    remote = _MockRemote();
    desktops = _MockDesktops();
    store = _MockStore();
    repository = PairingRepositoryImp(remote, desktops, store);
  });

  test('identifies, saves with the daemon name, then sets the active config', () async {
    when(() => remote.identify(_target)).thenAnswer((_) async => const DesktopIdentityModel(name: 'Mac', hostname: 'mac.local'));
    when(() => desktops.save(any())).thenAnswer((_) async => Result.success(_saved));

    final result = await repository.verifyAndConnect(_target);

    expect(result.isSuccess, isTrue);
    final results = verifyInOrder([
      () => remote.identify(_target),
      () => desktops.save(captureAny()),
      () => store.set(_target),
    ]);
    final params = results[1].captured.single as SaveDesktopParams;
    expect(params.name, 'Mac');
    expect(params.password, 'secret12');
  });

  test('falls back to the address when the daemon sends no name', () async {
    when(() => remote.identify(_target)).thenAnswer((_) async => const DesktopIdentityModel());
    when(() => desktops.save(any())).thenAnswer((_) async => Result.success(_saved));

    await repository.verifyAndConnect(_target);

    final params = verify(() => desktops.save(captureAny())).captured.single as SaveDesktopParams;
    expect(params.name, '10.0.0.5:3011');
  });

  test('does not save or set when identify fails', () async {
    when(() => remote.identify(_target)).thenThrow(ServerFailure<Map<String, dynamic>>(error: 'x', message: 'no', statusCode: 401));

    final result = await repository.verifyAndConnect(_target);

    expect(result.isFailure, isTrue);
    verifyNever(() => desktops.save(any()));
    verifyNever(() => store.set(any()));
  });
}
