import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

abstract class ChatEventDataSource {
  Stream<ConversationEventModel> stream({
    required int after,
    required CancelToken cancelToken,
  });
}

class ChatEventDataSourceImp implements ChatEventDataSource {
  ChatEventDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Stream<ConversationEventModel> stream({
    required int after,
    required CancelToken cancelToken,
  }) {
    late StreamController<ConversationEventModel> controller;
    StreamSubscription<String>? subscription;
    var canceled = false;
    var paused = false;

    Future<void> start() async {
      try {
        final response = await _apiConsumer.get(
          EndPoints.events,
          queryParameters: {'after': max(0, after)},
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
            headers: const {'Accept': 'text/event-stream'},
          ),
          cancelToken: cancelToken,
        );

        final body = response.data as ResponseBody;
        var buffer = '';
        subscription = const Utf8Decoder(allowMalformed: true)
            .bind(body.stream)
            .listen(
              (chunk) {
                buffer += chunk;
                final split = takeSseFrames(buffer);
                buffer = split.remainder;
                for (final frame in split.frames) {
                  final event = parseSseFrame(frame);
                  if (event != null) controller.add(event);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!canceled) controller.addError(error, stackTrace);
              },
              onDone: () {
                if (!canceled) controller.close();
              },
            );
        if (canceled) {
          await subscription!.cancel();
        } else if (paused) {
          subscription!.pause();
        }
      } catch (error, stackTrace) {
        if (!canceled) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      }
    }

    controller = StreamController<ConversationEventModel>(
      onListen: start,
      onPause: () {
        paused = true;
        subscription?.pause();
      },
      onResume: () {
        paused = false;
        subscription?.resume();
      },
      onCancel: () async {
        canceled = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
