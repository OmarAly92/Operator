import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/chat/data/sse.dart';

void main() {
  group('mobile conversation SSE', () {
    test('keeps an incomplete tail while reading multiple LF frames', () {
      final result = takeSseFrames('id: 1\ndata: {"seq":1}\n\nid: 2\ndata: {"seq":2}\n\nid: 3\nda');
      expect(result.frames, hasLength(2));
      expect(result.remainder, 'id: 3\nda');
    });

    test('accepts CRLF boundaries from proxies', () {
      final result = takeSseFrames('id: 4\r\ndata: {"seq":4}\r\n\r\n');
      expect(result.frames, ['id: 4\r\ndata: {"seq":4}']);
      expect(parseSseFrame(result.frames.first)?.seq, 4);
    });

    test('uses the SSE id when old daemons omit seq and ignores malformed data', () {
      expect(parseSseFrame('id: 9\ndata: {"projectId":"p","type":"session_updated"}')?.seq, 9);
      expect(parseSseFrame('id: 10\ndata: nope'), isNull);
    });

    test('reports whether an event touches a conversation', () {
      final touching = parseSseFrame('id: 1\ndata: {"seq":1,"payload":{"conversationId":"c-1"}}');
      expect(touching?.touchesConversation, isTrue);
      expect(parseSseFrame('id: 2\ndata: {"seq":2}')?.touchesConversation, isFalse);
    });

    test('drops a frame with no data line at all', () {
      expect(parseSseFrame('id: 3\n: keep-alive'), isNull);
    });
  });
}
