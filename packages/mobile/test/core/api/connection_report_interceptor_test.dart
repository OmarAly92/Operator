import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/interceptors/connection_report_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      respond(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  final at = DateTime.utc(2026, 9, 25, 9);

  Future<List<ConnectionReport>> outcomeOf(
    Future<ResponseBody> Function(RequestOptions options) respond, {
    Options? options,
  }) async {
    final reports = ConnectionReports();
    final seen = <ConnectionReport>[];
    reports.stream.listen(seen.add);
    final dio = Dio(BaseOptions(baseUrl: 'http://10.0.0.5:3011'))
      ..httpClientAdapter = _Adapter(respond)
      ..interceptors.add(ConnectionReportInterceptor(reports, clock: () => at));
    try {
      await dio.get<dynamic>(EndPoints.sessions, options: options);
    } on DioException {
      return seen;
    }
    return seen;
  }

  ResponseBody json(int status) => ResponseBody.fromString(
    '{}',
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  test('a response means online', () async {
    expect(await outcomeOf((_) async => json(200)), [
      ConnectionReport(ConnectionOutcome.online, path: EndPoints.sessions, at: at),
    ]);
  });

  test('a 4xx other than auth and rate limit still means the desktop answered', () async {
    expect((await outcomeOf((_) async => json(404))).single.outcome, ConnectionOutcome.online);
  });

  test('401 and 403 mean auth', () async {
    expect((await outcomeOf((_) async => json(401))).single.outcome, ConnectionOutcome.auth);
    expect((await outcomeOf((_) async => json(403))).single.outcome, ConnectionOutcome.auth);
  });

  test('429 means rate-limited', () async {
    expect((await outcomeOf((_) async => json(429))).single.outcome, ConnectionOutcome.rateLimited);
  });

  test('5xx means a server error', () async {
    expect((await outcomeOf((_) async => json(503))).single.outcome, ConnectionOutcome.serverError);
  });

  test('timeouts and connection errors mean unreachable', () async {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.connectionError,
    ]) {
      final seen = await outcomeOf((options) async => throw DioException(requestOptions: options, type: type));
      expect(seen.single.outcome, ConnectionOutcome.unreachable, reason: type.name);
    }
  });

  test('a pairing probe aimed at an unsaved desktop reports nothing', () async {
    final seen = await outcomeOf(
      (_) async => json(401),
      options: Options(
        extra: {'pairingTarget': const ServerConfig(host: 'h', httpPort: '1', secure: false, password: 'p')},
      ),
    );

    expect(seen, isEmpty);
  });

  test('a cancelled request reports nothing', () async {
    final seen = await outcomeOf(
      (options) async => throw DioException(requestOptions: options, type: DioExceptionType.cancel),
    );

    expect(seen, isEmpty);
  });
}
