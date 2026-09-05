import 'package:dio/dio.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

ServerFailure<Map<String, dynamic>> handleDioError(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return ServerFailure<Map<String, dynamic>>(
        error: error,
        message: 'Could not reach your Operator server',
        statusCode: StatusCode.noInternetConnection,
      );
    default:
      break;
  }

  final body = error.response?.data;
  if (body is! Map<String, dynamic>) {
    return ServerFailure<Map<String, dynamic>>(
      error: error,
      message: error.message ?? 'Request failed',
      statusCode: error.response?.statusCode,
    );
  }

  final requestId = body['requestId'];
  final rawMessage = body['message'];
  final rawError = body['error'];
  final message = rawMessage is String
      ? rawMessage
      : rawError is String
          ? rawError
          : 'Request failed';
  final rawCode = body['code'];
  final apiStatus = rawCode is String ? rawCode : null;
  final rawDetails = body['details'];
  final details = rawDetails is Map<String, dynamic> ? rawDetails : const <String, dynamic>{};
  // requestId is spread LAST: it is the envelope's own field and must win over
  // a same-named key that happens to appear inside a server's details map.
  final extras = <String, dynamic>{
    ...details,
    if (requestId is String) 'requestId': requestId,
  };
  return ServerFailure<Map<String, dynamic>>(
    error: error,
    message: message,
    statusCode: error.response?.statusCode,
    apiStatus: apiStatus,
    validationErrors: extras.isEmpty ? null : extras,
  );
}
