import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';

DioException _exception(Map<String, dynamic> body, int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/sessions'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/v1/sessions'),
        statusCode: statusCode,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('handleDioError', () {
    test('keeps the daemon code and requestId', () {
      final failure = handleDioError(
        _exception({
          'error': 'conflict',
          'code': 'SESSION_AWAITING_DECISION',
          'message': 'Session is awaiting a decision',
          'requestId': 'req_01H',
        }, 409),
      );

      expect(failure.message, 'Session is awaiting a decision');
      expect(failure.apiStatus, 'SESSION_AWAITING_DECISION');
      expect(failure.statusCode, 409);
      expect(failure.validationErrors, {'requestId': 'req_01H'});
    });

    test('falls back to error when message is absent', () {
      final failure = handleDioError(_exception({'error': 'bad request'}, 400));

      expect(failure.message, 'bad request');
      expect(failure.apiStatus, isNull);
    });

    test('falls back to a default message when message is not a string', () {
      final failure = handleDioError(
        _exception({'message': 12345, 'code': 'X'}, 500),
      );

      expect(failure.message, 'Request failed');
      expect(failure.apiStatus, 'X');
    });

    test('maps a timeout to a network failure', () {
      final failure = handleDioError(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/sessions'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(failure.statusCode, StatusCode.noInternetConnection);
    });
  });
}
