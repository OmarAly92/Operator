import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/save_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

class _MockLocal extends Mock implements DesktopsLocalDataSource {}

const _params = SaveDesktopParams(name: 'Mac', host: 'h', port: '1', secure: false, password: 'p');
const _model = DesktopModel(id: 'a', name: 'Mac', host: 'h', port: '1', secure: false, isActive: true);

void main() {
  late _MockLocal local;
  late DesktopsRepositoryImp repository;

  setUpAll(() => registerFallbackValue(_params));

  setUp(() {
    local = _MockLocal();
    repository = DesktopsRepositoryImp(local);
  });

  test('save returns the saved model', () async {
    when(() => local.save(any())).thenAnswer((_) async => _model);
    final result = await repository.save(_params);
    expect(result.isSuccess, isTrue);
    result.when(onSuccess: (m) => expect(m, _model), onFailure: (_) => fail('failure'));
  });

  test('a LocalFailure from the data source becomes a failure result', () async {
    when(() => local.remove('a')).thenThrow(LocalFailure<void>(error: 'disk'));
    final result = await repository.remove('a');
    expect(result.isFailure, isTrue);
  });

  test('activate forwards the identified name', () async {
    when(() => local.activate('a', name: 'Mac')).thenAnswer((_) async {});
    final result = await repository.activate('a', name: 'Mac');
    expect(result.isSuccess, isTrue);
    verify(() => local.activate('a', name: 'Mac')).called(1);
  });

  test('watchDesktops passes the stream through', () {
    when(() => local.watchAll()).thenAnswer((_) => Stream.value([_model]));
    expect(repository.watchDesktops(), emits([_model]));
  });
}
