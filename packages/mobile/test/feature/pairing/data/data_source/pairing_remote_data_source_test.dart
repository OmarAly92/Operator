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

  test('pings /sessions with the candidate config as a pairingTarget override', () async {
    when(() => api.get(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Response<dynamic>(requestOptions: RequestOptions(path: EndPoints.sessions), statusCode: 200),
    );

    await dataSource.ping(_target);

    final captured = verify(() => api.get(EndPoints.sessions, options: captureAny(named: 'options'))).captured;
    final options = captured.single as Options;
    expect(options.extra?['pairingTarget'], _target);
  });

  test('lets a Failure bubble uncaught', () {
    when(() => api.get(any(), options: any(named: 'options'))).thenThrow(ServerFailure.noNetwork());

    expect(() => dataSource.ping(_target), throwsA(isA<ServerFailure>()));
  });
}
