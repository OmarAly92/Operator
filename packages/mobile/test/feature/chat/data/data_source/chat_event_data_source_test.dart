import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _FakeCancelToken extends Fake implements CancelToken {}

void main() {
  late _MockApiConsumer apiConsumer;
  late ChatEventDataSource dataSource;
  late StreamController<Uint8List> chunks;
  late Completer<void> bodyCanceled;

  setUpAll(() => registerFallbackValue(_FakeCancelToken()));

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = ChatEventDataSourceImp(apiConsumer);
    bodyCanceled = Completer<void>();
    chunks = StreamController<Uint8List>(onCancel: bodyCanceled.complete);

    when(
      () => apiConsumer.get(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: EndPoints.events),
        data: ResponseBody(chunks.stream, 200),
      ),
    );
  });

  tearDown(() => chunks.close());

  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

  test(
    'asks the daemon to replay from the cursor with no receive timeout',
    () async {
      final events = dataSource
          .stream(after: const CdcCursor.at(7), cancelToken: CancelToken())
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);

      final call = verify(
        () => apiConsumer.get(
          EndPoints.events,
          queryParameters: captureAny(named: 'queryParameters'),
          options: captureAny(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;

      expect(call[0], {'after': 7});
      final options = call[1] as Options;
      expect(options.responseType, ResponseType.stream);
      expect(options.receiveTimeout, Duration.zero);
      expect(options.headers!['Accept'], 'text/event-stream');
      await events.cancel();
    },
  );

  test('never asks for a negative cursor', () async {
    final events = dataSource
        .stream(after: const CdcCursor.at(-4), cancelToken: CancelToken())
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final captured =
        verify(
              () => apiConsumer.get(
                any(),
                queryParameters: captureAny(named: 'queryParameters'),
                options: any(named: 'options'),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(captured, {'after': 0});
    await events.cancel();
  });

  test('cancels the idle response body subscription promptly', () async {
    final events = dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);

    await events.cancel().timeout(const Duration(seconds: 1));
    await bodyCanceled.future.timeout(const Duration(seconds: 1));
  });

  test('emits parsed events and survives a chunk split mid-frame', () async {
    final received = <int>[];
    final events = dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((event) => received.add(event.seq));
    await Future<void>.delayed(Duration.zero);

    chunks.add(
      bytes('id: 1\ndata: {"seq":1,"sessionId":"w-1"}\n\nid: 2\ndata: {"se'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, [1]);

    chunks.add(bytes('q":2,"sessionId":"w-1"}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [1, 2]);

    chunks.add(bytes('id: 3\ndata: broken\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [1, 2]);

    await events.cancel();
  });

  test('preserves a UTF-8 character split across transport chunks', () async {
    final received = <ConversationEventModel>[];
    final events = dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen(received.add);
    await Future<void>.delayed(Duration.zero);

    final prefix = utf8.encode('id: 1\ndata: {"seq":1,"payload":{"message":"');
    final character = utf8.encode('👋');
    chunks.add(Uint8List.fromList([...prefix, ...character.take(2)]));
    chunks.add(
      Uint8List.fromList([...character.skip(2), ...utf8.encode('"}}\n\n')]),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.single.payload, {'message': '👋'});
    await events.cancel();
  });

  test('forwards response body errors', () async {
    final streamError = StateError('body failed');
    final receivedErrors = <Object>[];
    final done = Completer<void>();
    dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((_) {}, onError: receivedErrors.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);

    chunks.addError(streamError);
    await chunks.close();
    await done.future.timeout(const Duration(seconds: 1));

    expect(receivedErrors, [same(streamError)]);
  });

  test('forwards request errors and closes the stream', () async {
    final requestError = StateError('request failed');
    final receivedErrors = <Object>[];
    final done = Completer<void>();
    reset(apiConsumer);
    when(
      () => apiConsumer.get(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => throw requestError);

    dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((_) {}, onError: receivedErrors.add, onDone: done.complete);
    await done.future.timeout(const Duration(seconds: 1));

    expect(receivedErrors, [same(requestError)]);
    final drain = chunks.stream.drain<void>();
    await chunks.close();
    await drain;
  });

  test('closes when the daemon ends the stream', () async {
    final done = Completer<void>();
    dataSource
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((_) {}, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);

    await chunks.close();
    await done.future.timeout(const Duration(seconds: 1));
  });

  test('errors and closes when the server stops sending anything', () async {
    final source = ChatEventDataSourceImp(
      apiConsumer,
      staleAfter: const Duration(milliseconds: 40),
    );
    final errors = <Object>[];
    var closed = false;

    source.stream(after: const CdcCursor.at(0), cancelToken: CancelToken()).listen(
      (_) {},
      onError: errors.add,
      onDone: () => closed = true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(errors.single, isA<StaleEventStreamException>());
    expect(closed, isTrue);
  });

  test('a keepalive comment frame keeps the stream alive', () async {
    final source = ChatEventDataSourceImp(
      apiConsumer,
      staleAfter: const Duration(milliseconds: 60),
    );
    final errors = <Object>[];

    source
        .stream(after: const CdcCursor.at(0), cancelToken: CancelToken())
        .listen((_) {}, onError: errors.add);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    chunks.add(bytes(': keepalive\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(errors, isEmpty);
  });
}
