import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/mux/mux_backoff.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_socket.dart';

class _FakeMuxSocket implements MuxSocket {
  final _incoming = StreamController<dynamic>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  void pushMessage(Map<String, dynamic> message) => _incoming.add(jsonEncode(message));

  void closeFromServer() => _incoming.close();
}

class _SlowFakeMuxSocket implements MuxSocket {
  _SlowFakeMuxSocket(this._readyFuture);

  final Future<void> _readyFuture;
  final _incoming = StreamController<dynamic>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  Future<void> get ready => _readyFuture;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}

const _config = ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12');

class _StubSource implements ServerConfigSource {
  @override
  ServerConfig? current = _config;
}

late _StubSource _source;

void main() {
  group('MuxClient', () {
    setUp(() => _source = _StubSource());

    test('sends the auth header and no Origin on connect', () {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      final client = MuxClient(
        _source,
        connect: (uri, headers) {
          capturedUri = uri;
          capturedHeaders = headers;
          return _FakeMuxSocket();
        },
      );

      client.connect();

      expect(capturedUri, Uri.parse('ws://10.0.0.5:3011/mux'));
      expect(capturedHeaders?.containsKey('Origin'), isFalse, reason: 'the daemon CORS allowlist 403s any Origin');
      expect(capturedHeaders?['Authorization'], 'Bearer secret12');
    });

    test('re-reads the server config on every connect so re-pairing retargets the socket', () {
      fakeAsync((async) {
        final uris = <Uri>[];
        late _FakeMuxSocket socket;
        final client = MuxClient(
          _source,
          connect: (uri, _) {
            uris.add(uri);
            return socket = _FakeMuxSocket();
          },
        );

        client.connect();
        async.flushMicrotasks();
        expect(uris.single, Uri.parse('ws://10.0.0.5:3011/mux'));

        _source.current = const ServerConfig(
          host: '10.0.0.9',
          httpPort: '3011',
          secure: false,
          password: 'secret12',
        );
        socket.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();

        expect(uris.last, Uri.parse('ws://10.0.0.9:3011/mux'));
        client.disconnect();
      });
    });

    test('retries instead of connecting when no server is paired', () {
      fakeAsync((async) {
        var connectCount = 0;
        _source.current = null;
        final client = MuxClient(
          _source,
          connect: (_, _) {
            connectCount++;
            return _FakeMuxSocket();
          },
        );

        client.connect();
        async.flushMicrotasks();
        expect(connectCount, 0);

        _source.current = _config;
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();
        expect(connectCount, 1);

        client.disconnect();
      });
    });

    test('decodes a sessions snapshot into SessionPatch', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      final patches = <List<dynamic>>[];
      client.sessionPatches.listen(patches.add);

      socket.pushMessage({
        'ch': 'sessions',
        'type': 'snapshot',
        'sessions': [
          {'id': 'proj-1', 'status': 'working', 'activity': 'active', 'attentionLevel': 'working', 'lastActivityAt': 't'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(patches, hasLength(1));
      expect(patches.first, hasLength(1));
      expect((patches.first.first as dynamic).id, 'proj-1');
    });

    test('decodes base64 terminal data', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      final events = <dynamic>[];
      client.terminalEvents.listen(events.add);

      socket.pushMessage({'ch': 'terminal', 'id': 's1', 'type': 'data', 'data': base64Encode(utf8.encode('hi'))});
      await Future<void>.delayed(Duration.zero);

      final event = events.single as TerminalDataEvent;
      expect(event.id, 's1');
      expect(utf8.decode(event.bytes), 'hi');
    });

    test('sendInput base64-encodes the payload', () async {
      late _FakeMuxSocket socket;
      final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
      client.connect();
      await Future<void>.delayed(Duration.zero);

      client.sendInput('s1', 'ls -la', projectId: 'p1');

      final sent = jsonDecode(socket.sent.last) as Map<String, dynamic>;
      expect(sent['ch'], 'terminal');
      expect(sent['type'], 'data');
      expect(sent['data'], base64Encode(utf8.encode('ls -la')));
      expect(sent['projectId'], 'p1');
    });

    test('re-subscribes and re-opens tracked terminals after a reconnect, with doubling backoff', () {
      fakeAsync((async) {
        var connectCount = 0;
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(
          _source,
          connect: (_, _) {
            connectCount++;
            final socket = _FakeMuxSocket();
            sockets.add(socket);
            return socket;
          },
        );

        client.connect();
        async.flushMicrotasks();
        expect(connectCount, 1);

        client.subscribeSessions();
        client.openTerminal('s1', projectId: 'p1');
        expect(sockets[0].sent, hasLength(2));

        sockets[0].closeFromServer();
        async.elapse(Duration(milliseconds: MuxBackoff.initialMs - 1));
        expect(connectCount, 1, reason: 'reconnect not due yet');

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(connectCount, 2);

        final replayed = sockets[1].sent.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
        expect(replayed.any((m) => m['ch'] == 'subscribe'), isTrue);
        expect(replayed.any((m) => m['ch'] == 'terminal' && m['id'] == 's1' && m['type'] == 'open'), isTrue);

        sockets[1].closeFromServer();
        async.elapse(const Duration(milliseconds: 2000));
        async.flushMicrotasks();
        expect(connectCount, 3);

        client.disconnect();
      });
    });

    test('sends a ping every 20 seconds while connected', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 20));
        final pings = socket.sent.map((s) => jsonDecode(s) as Map<String, dynamic>).where((m) => m['ch'] == 'system');
        expect(pings, hasLength(1));

        client.disconnect();
      });
    });

    test('disconnect suppresses the reconnect', () {
      fakeAsync((async) {
        var connectCount = 0;
        late _FakeMuxSocket socket;
        final client = MuxClient(
          _source,
          connect: (_, _) {
            connectCount++;
            return socket = _FakeMuxSocket();
          },
        );
        client.connect();
        async.flushMicrotasks();
        expect(connectCount, 1);

        client.disconnect();
        socket.closeFromServer();
        async.elapse(const Duration(seconds: 20));
        expect(connectCount, 1);
      });
    });

    test('disconnect while a connect is in flight suppresses the pending open', () async {
      final readyCompleter = Completer<void>();
      late _SlowFakeMuxSocket socket;
      final statuses = <MuxStatus>[];
      final client = MuxClient(
        _source,
        connect: (_, _) => socket = _SlowFakeMuxSocket(readyCompleter.future),
      );
      client.status.listen(statuses.add);

      client.connect();
      await Future<void>.delayed(Duration.zero);

      client.disconnect();
      readyCompleter.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(statuses, isNot(contains(MuxStatus.open)));
      expect(socket.closed, isTrue);
      expect(socket.sent, isEmpty);
    });

    test('remembers the current status for late subscribers', () async {
      final socket = _FakeMuxSocket();
      final client = MuxClient(_source, connect: (_, _) => socket);

      expect(client.currentStatus, MuxStatus.closed);

      client.connect();
      await Future<void>.delayed(Duration.zero);

      expect(client.currentStatus, MuxStatus.open);

      await client.disconnect();
    });

    test('subscribes to a session\'s blocks and surfaces its events', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        final seen = <BlockEventEnvelope>[];
        client.blockEvents.listen(seen.add);
        client.subscribeBlocks('s-1');
        async.flushMicrotasks();

        final sent = socket.sent.map((raw) => jsonDecode(raw) as Map<String, dynamic>).toList();
        expect(
          sent.any((m) => m['ch'] == 'blocks' && m['id'] == 's-1' && m['type'] == 'subscribe'),
          isTrue,
        );

        socket.pushMessage({
          'ch': 'blocks',
          'id': 's-1',
          'type': 'block',
          'block': {'seq': 7, 'sessionId': 's-1', 'kind': 'tool_complete', 'toolName': 'Bash'},
        });
        async.flushMicrotasks();

        expect(seen, hasLength(1));
        expect(seen.single.sessionId, 's-1');
        expect(seen.single.block['seq'], 7);
        expect(seen.single.block['toolName'], 'Bash');
        client.disconnect();
      });
    });

    test('re-subscribes every block session after a reconnect', () {
      fakeAsync((async) {
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(_source, connect: (_, _) {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        });
        client.connect();
        async.flushMicrotasks();

        client.subscribeBlocks('s-1');
        client.subscribeBlocks('s-2');
        async.flushMicrotasks();

        sockets.first.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();

        final resent = sockets.last.sent.map((raw) => jsonDecode(raw) as Map<String, dynamic>).toList();
        expect(
          resent.any((m) => m['ch'] == 'blocks' && m['id'] == 's-1' && m['type'] == 'subscribe'),
          isTrue,
        );
        expect(
          resent.any((m) => m['ch'] == 'blocks' && m['id'] == 's-2' && m['type'] == 'subscribe'),
          isTrue,
        );
        client.disconnect();
      });
    });

    test('unsubscribing tells the daemon and survives a reconnect', () {
      fakeAsync((async) {
        final sockets = <_FakeMuxSocket>[];
        final client = MuxClient(_source, connect: (_, _) {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        });
        client.connect();
        async.flushMicrotasks();

        client.subscribeBlocks('s-1');
        client.unsubscribeBlocks('s-1');
        async.flushMicrotasks();

        final sent = sockets.first.sent.map((raw) => jsonDecode(raw) as Map<String, dynamic>).toList();
        expect(
          sent.any((m) => m['ch'] == 'blocks' && m['id'] == 's-1' && m['type'] == 'unsubscribe'),
          isTrue,
        );

        sockets.first.closeFromServer();
        async.elapse(const Duration(milliseconds: MuxBackoff.initialMs));
        async.flushMicrotasks();

        final resent = sockets.last.sent.map((raw) => jsonDecode(raw)).toList();
        expect(
          resent.any((frame) => frame is Map && frame['ch'] == 'blocks'),
          isFalse,
          reason: 'an unsubscribed session must not come back on reconnect',
        );
        client.disconnect();
      });
    });

    test('ignores a blocks frame with no payload', () {
      fakeAsync((async) {
        late _FakeMuxSocket socket;
        final client = MuxClient(_source, connect: (_, _) => socket = _FakeMuxSocket());
        client.connect();
        async.flushMicrotasks();

        final seen = <BlockEventEnvelope>[];
        client.blockEvents.listen(seen.add);
        client.subscribeBlocks('s-1');
        socket.pushMessage({'ch': 'blocks', 'id': 's-1', 'type': 'block'});
        socket.pushMessage({'ch': 'blocks', 'id': 's-1', 'type': 'block', 'block': 'not-a-map'});
        async.flushMicrotasks();

        expect(seen, isEmpty);
        client.disconnect();
      });
    });
  });
}
