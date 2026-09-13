import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/events/sse_stream.dart';

class _MockApi extends Mock implements ApiConsumer {}

void main() {
  test(
    'frames split across chunks invalidate once and cancellation aborts HTTP',
    () async {
      final api = _MockApi();
      final bytes = StreamController<Uint8List>();
      CancelToken? token;
      when(
        () => api.get(
          any(),
          options: any(named: 'options'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        token = invocation.namedArguments[#cancelToken] as CancelToken;
        final options = invocation.namedArguments[#options] as Options;
        expect(options.responseType, ResponseType.stream);
        expect(options.receiveTimeout, Duration.zero);
        return Response(
          requestOptions: RequestOptions(path: '/events'),
          data: ResponseBody(bytes.stream, 200),
        );
      });
      final received = <SseStreamEvent>[];
      final subscription = watchSse(api, '/events').listen(received.add);
      await Future<void>.delayed(Duration.zero);
      for (final chunk in [
        ': heartbeat\r\n\r\nevent: update\r\nda',
        'ta: {}\r\n',
        '\r\n',
      ]) {
        bytes.add(Uint8List.fromList(utf8.encode(chunk)));
      }
      await Future<void>.delayed(Duration.zero);
      expect(received, [SseStreamEvent.connected, SseStreamEvent.changed]);
      await subscription.cancel();
      expect(token!.isCancelled, isTrue);
      await bytes.close();
    },
  );
}
