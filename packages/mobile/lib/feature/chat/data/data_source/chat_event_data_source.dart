import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

const Duration kEventStreamStaleAfter = Duration(seconds: 35);

class StaleEventStreamException implements Exception {
  const StaleEventStreamException(this.silentFor);

  final Duration silentFor;

  @override
  String toString() =>
      'StaleEventStreamException: no server traffic for $silentFor';
}

/// One item from the live event stream.
///
/// The stream carries a connection signal as well as events because
/// `.listen()` returning proves nothing: the HTTP request is only issued on
/// first listen, so a subscriber that treats subscription as connection reports
/// "connected" against an unreachable daemon until the connect timeout expires.
sealed class ConversationStreamFrame {
  const ConversationStreamFrame();
}

/// The daemon answered and the body is streaming. Proof of connection.
final class ConversationStreamOpened extends ConversationStreamFrame {
  const ConversationStreamOpened();
}

final class ConversationStreamEvent extends ConversationStreamFrame {
  const ConversationStreamEvent(this.event);

  final ConversationEventModel event;
}

abstract class ChatEventDataSource {
  Stream<ConversationStreamFrame> stream({
    required CdcCursor after,
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
  Stream<ConversationStreamFrame> stream({
    required CdcCursor after,
    required CancelToken cancelToken,
  }) {
    late StreamController<ConversationStreamFrame> controller;
    StreamSubscription<String>? subscription;
    var canceled = false;
    var paused = false;
    Timer? staleTimer;

    void stopStaleTimer() {
      staleTimer?.cancel();
      staleTimer = null;
    }

    // The server guarantees a comment frame every 15s (see events.go), so
    // silence past this window means the socket is dead. Dio cannot tell us:
    // receiveTimeout must stay disabled on a long-lived stream.
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
          queryParameters: after.queryParameters,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
            headers: const {'Accept': 'text/event-stream'},
          ),
          cancelToken: cancelToken,
        );

        final body = response.data as ResponseBody;
        if (!canceled && !controller.isClosed) {
          controller.add(const ConversationStreamOpened());
        }
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
                  if (event != null) {
                    controller.add(ConversationStreamEvent(event));
                  }
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
          stopStaleTimer();
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

    controller = StreamController<ConversationStreamFrame>(
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
