import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/events/sse_stream.dart';

export 'package:operator_mobile/core/events/sse_stream.dart'
    show SseStreamEvent;

abstract class NotificationStreamDataSource {
  Stream<SseStreamEvent> watch();
}

class NotificationStreamDataSourceImp implements NotificationStreamDataSource {
  NotificationStreamDataSourceImp(this._apiConsumer);

  final ApiConsumer _apiConsumer;

  @override
  Stream<SseStreamEvent> watch() =>
      watchSse(_apiConsumer, '/api/v1/notifications/stream');
}
