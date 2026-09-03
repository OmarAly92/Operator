import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

const Duration kEventStreamStaleAfter = Duration(seconds: 35);

class StaleEventStreamException implements Exception {
  const StaleEventStreamException(this.silentFor);

  final Duration silentFor;

  @override
  String toString() =>
      'StaleEventStreamException: no server traffic for $silentFor';
}

abstract class ChatEventDataSource {
  Stream<ConversationEventModel> stream({
    required int after,
    required CancelToken cancelToken,
  });
}

class ChatEventDataSourceImp implements ChatEventDataSource {
  ChatEventDataSourceImp(
    this._apiConsumer, {
    this._staleAfter = kEventStreamStaleAfter,
  });

  final ApiConsumer _apiConsumer;
  final Duration _staleAfter;

  @override
  Stream<ConversationEventModel> stream({
    required int after,
    required CancelToken cancelToken,
  }) {
    late StreamController<ConversationEventModel> controller;
    StreamSubscription<String>? subscription;
    var canceled = false;
    var paused = false;
    Timer? staleTimer;

    void stopStaleTimer() {
      staleTimer?.cancel();
      staleTimer = null;
    }

    void markAlive() {
      staleTimer?.cancel();
      staleTimer = Timer(_staleAfter, () {
        if (canceled) return;
        controller.addError(
          StaleEventStreamException(_staleAfter),
          StackTrace.current,
        );
        unawaited(subscription?.cancel());
        subscription = null;
        if (!controller.isClosed) unawaited(controller.close());
      });
    }

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
                markAlive();
                buffer += chunk;
                final split = takeSseFrames(buffer);
                buffer = split.remainder;
                for (final frame in split.frames) {
                  final event = parseSseFrame(frame);
                  if (event != null) controller.add(event);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                stopStaleTimer();
                if (!canceled) controller.addError(error, stackTrace);
              },
              onDone: () {
                stopStaleTimer();
                if (!canceled) controller.close();
              },
            );
        markAlive();
        if (canceled) {
          await subscription!.cancel();
        } else if (paused) {
          subscription!.pause();
        }
      } catch (error, stackTrace) {
        stopStaleTimer();
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
        stopStaleTimer();
        canceled = true;
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
