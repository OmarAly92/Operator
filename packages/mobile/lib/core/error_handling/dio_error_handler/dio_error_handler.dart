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
  return ServerFailure<Map<String, dynamic>>(
    error: error,
    message: (body['message'] ?? body['error'] ?? 'Request failed') as String,
    statusCode: error.response?.statusCode,
    apiStatus: body['code'] as String?,
    validationErrors: requestId is String ? {'requestId': requestId} : null,
  );
}
