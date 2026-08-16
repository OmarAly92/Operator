import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';
import 'package:operator_mobile/core/helpers/logging/app_logger.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

class DioConsumer implements ApiConsumer {
  DioConsumer(this._configSource) {
    setDefaultDioOptions();

    client.interceptors.add(ServerConfigInterceptor(_configSource));

    if (kDebugMode) {
      client.interceptors.add(
        TalkerDioLogger(
          talker: AppLogger.logger,
          settings: const TalkerDioLoggerSettings(
            printRequestHeaders: true,
            printRequestData: true,
            printResponseMessage: true,
          ),
        ),
      );
    }
  }

  final ServerConfigSource _configSource;

  @override
  final Dio client = Dio();

  @override
  set client(Dio _) {}

  @override
  void setDefaultDioOptions() {
    client.options
      ..headers = {
        'accept': 'application/json',
        'Content-Type': 'application/json',
      }
      ..connectTimeout = const Duration(seconds: 12)
      ..receiveTimeout = const Duration(seconds: 12);
  }

  @override
  Future<Response> get<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.get(
        path,
        queryParameters: queryParameters,
        data: body,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }

  @override
  Future<Response> post<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    bool formDataIsEnabled = false,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.post(
        path,
        queryParameters: queryParameters,
        data: body,
        options: options,
      );
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }

  @override
  Future<Response> put<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.put(path, queryParameters: queryParameters, data: body);
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }

  @override
  Future<Response> patch<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.patch(
        path,
        queryParameters: queryParameters,
        data: body,
      );
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }

  @override
  Future<Response> delete<T>(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Map<String, dynamic>)? errorFromJsonT,
  }) async {
    try {
      return await client.delete(
        path,
        queryParameters: queryParameters,
        data: body,
        options: options,
      );
    } on DioException catch (error) {
      throw handleDioError(error);
    }
  }
}
