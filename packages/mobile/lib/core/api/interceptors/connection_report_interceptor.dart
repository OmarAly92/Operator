import 'package:dio/dio.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';

class ConnectionReportInterceptor extends Interceptor {
  ConnectionReportInterceptor(this._reports, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ConnectionReports _reports;
  final DateTime Function() _clock;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _report(response.requestOptions, ConnectionOutcome.online);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final outcome = _outcomeOf(err);
    if (outcome != null) _report(err.requestOptions, outcome);
    handler.next(err);
  }

  void _report(RequestOptions options, ConnectionOutcome outcome) {
    if (options.extra['pairingTarget'] != null) return;
    _reports.add(ConnectionReport(outcome, path: options.path, at: _clock()));
  }

  static ConnectionOutcome? _outcomeOf(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate => ConnectionOutcome.unreachable,
    DioExceptionType.badResponse => _fromStatus(error.response?.statusCode),
    DioExceptionType.cancel || DioExceptionType.unknown => null,
  };

  static ConnectionOutcome _fromStatus(int? status) {
    if (status == 401 || status == 403) return ConnectionOutcome.auth;
    if (status == 429) return ConnectionOutcome.rateLimited;
    if (status != null && status >= 500) return ConnectionOutcome.serverError;
    return ConnectionOutcome.online;
  }
}
