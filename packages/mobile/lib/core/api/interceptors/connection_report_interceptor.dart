import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/dio_error_handler.dart';

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
    final sentTo = options.extra[kSentToExtra];
    _reports.add(
      ConnectionReport(outcome, path: options.path, at: _clock(), sentTo: sentTo is ServerConfig ? sentTo : null),
    );
  }

  static ConnectionOutcome? _outcomeOf(DioException error) {
    if (isTransportFailure(error)) return ConnectionOutcome.unreachable;
    if (error.type == DioExceptionType.badResponse) return _fromStatus(error.response?.statusCode);
    return null;
  }

  static ConnectionOutcome _fromStatus(int? status) {
    if (status == 401) return ConnectionOutcome.auth;
    if (status == 429) return ConnectionOutcome.rateLimited;
    if (status != null && status >= 500) return ConnectionOutcome.serverError;
    return ConnectionOutcome.online;
  }
}
