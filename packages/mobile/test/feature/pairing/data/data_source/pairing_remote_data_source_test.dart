import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

const _target = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

void main() {
  late _MockApiConsumer api;
  late PairingRemoteDataSourceImp dataSource;

  setUp(() {
    api = _MockApiConsumer();
    dataSource = PairingRemoteDataSourceImp(api);
  });

  test('identify hits /api/v1/desktop with the pairing target and parses the name', () async {
    when(() => api.get(EndPoints.desktop, options: any(named: 'options'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: EndPoints.desktop),
        data: {'name': 'Omars MacBook Pro 9', 'hostname': 'Omars-MacBook-Pro-9.local'},
      ),
    );

    final identity = await dataSource.identify(_target);

    expect(identity.name, 'Omars MacBook Pro 9');
    final options = verify(() => api.get(EndPoints.desktop, options: captureAny(named: 'options'))).captured.single as Options;
    expect(options.extra?['pairingTarget'], _target);
  });

  test('lets a Failure bubble uncaught', () {
    when(() => api.get(any(), options: any(named: 'options'))).thenThrow(ServerFailure.noNetwork());

    expect(() => dataSource.identify(_target), throwsA(isA<ServerFailure>()));
  });
}
