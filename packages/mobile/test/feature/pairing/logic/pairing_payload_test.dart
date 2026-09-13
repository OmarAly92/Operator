import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/pairing_payload.dart';

void main() {
  group('parsePairingPayload', () {
    test('parses a full payload', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}');
      expect(payload, const PairingPayload(host: '10.0.0.5', port: '3011', password: 'secret12', secure: false));
    });

    test('accepts a numeric port', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":3011}');
      expect(payload?.port, '3011');
      expect(payload?.password, '');
    });

    test('rejects a missing version', () {
      expect(parsePairingPayload('{"host":"10.0.0.5","port":"3011"}'), isNull);
    });

    test('rejects a version newer than we understand', () {
      expect(parsePairingPayload('{"v":99,"url":"https://x.ngrok-free.dev"}'), isNull);
      expect(pairingPayloadVersion('{"v":99,"url":"https://x.ngrok-free.dev"}'), 99);
    });

    test('v1 stays insecure with its host and port', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}');
      expect(payload, const PairingPayload(host: '10.0.0.5', port: '3011', password: 'secret12', secure: false));
    });

    test('parses a v2 tunnel payload as a secure host on 443', () {
      final payload = parsePairingPayload(
        '{"v":2,"url":"https://imagines-livestock-widely.ngrok-free.dev","password":"averylongtunnelpassword"}',
      );
      expect(payload?.host, 'imagines-livestock-widely.ngrok-free.dev');
      expect(payload?.port, '443');
      expect(payload?.secure, isTrue);
      expect(payload?.password, 'averylongtunnelpassword');
    });

    test('honours an explicit port in a v2 url', () {
      final payload = parsePairingPayload('{"v":2,"url":"https://example.com:8443","password":"pw"}');
      expect(payload?.host, 'example.com');
      expect(payload?.port, '8443');
      expect(payload?.secure, isTrue);
    });

    test('rejects a v2 payload without a url', () {
      expect(parsePairingPayload('{"v":2,"password":"pw"}'), isNull);
    });

    test('rejects a v2 url that is not https', () {
      expect(parsePairingPayload('{"v":2,"url":"http://plain.example","password":"pw"}'), isNull);
      expect(parsePairingPayload('{"v":2,"url":"ftp://nope.example","password":"pw"}'), isNull);
    });

    test('rejects a malformed v2 url', () {
      expect(parsePairingPayload('{"v":2,"url":"https://","password":"pw"}'), isNull);
      expect(parsePairingPayload('{"v":2,"url":"not a url","password":"pw"}'), isNull);
    });

    test('reports the version for recognised payloads too', () {
      expect(pairingPayloadVersion('{"v":1,"host":"10.0.0.5","port":"3011"}'), 1);
      expect(pairingPayloadVersion('{"v":2,"url":"https://x.example"}'), 2);
      expect(pairingPayloadVersion('not json'), isNull);
      expect(pairingPayloadVersion('{"host":"10.0.0.5"}'), isNull);
    });

    test('rejects an empty or missing host', () {
      expect(parsePairingPayload('{"v":1,"host":"","port":"3011"}'), isNull);
      expect(parsePairingPayload('{"v":1,"port":"3011"}'), isNull);
    });

    test('rejects a missing or wrongly-typed port', () {
      expect(parsePairingPayload('{"v":1,"host":"10.0.0.5"}'), isNull);
      expect(parsePairingPayload('{"v":1,"host":"10.0.0.5","port":true}'), isNull);
    });

    test('rejects malformed JSON and non-object payloads', () {
      expect(parsePairingPayload('not json'), isNull);
      expect(parsePairingPayload('"a string"'), isNull);
      expect(parsePairingPayload('[1,2,3]'), isNull);
    });
  });
}
