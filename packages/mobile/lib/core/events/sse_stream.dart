import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';

enum SseStreamEvent { connected, changed }

Stream<SseStreamEvent> watchSse(
  ApiConsumer apiConsumer,
  String path, {
  Map<String, dynamic>? queryParameters,
}) {
  final cancelToken = CancelToken();
  StreamSubscription<String>? subscription;
  late final StreamController<SseStreamEvent> controller;
  controller = StreamController<SseStreamEvent>(
    onListen: () async {
      try {
        final response = await apiConsumer.get(
          path,
          queryParameters: queryParameters,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
          ),
          cancelToken: cancelToken,
        );
        if (cancelToken.isCancelled) return;
        controller.add(SseStreamEvent.connected);
        var hasData = false;
        subscription = (response.data as ResponseBody).stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (line.startsWith('data:')) hasData = true;
                if (line.isEmpty && hasData) {
                  hasData = false;
                  controller.add(SseStreamEvent.changed);
                }
              },
              onError: controller.addError,
              onDone: controller.close,
            );
      } catch (error, stack) {
        if (!cancelToken.isCancelled) {
          controller.addError(error, stack);
          unawaited(controller.close());
        }
      }
    },
    onCancel: () async {
      cancelToken.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
