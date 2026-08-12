import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/pairing_payload.dart';

void main() {
  group('parsePairingPayload', () {
    test('parses a full payload', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}');
      expect(payload, const PairingPayload(host: '10.0.0.5', port: '3011', password: 'secret12'));
    });

    test('accepts a numeric port', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":3011}');
      expect(payload?.port, '3011');
      expect(payload?.password, '');
    });

    test('rejects a wrong or missing version', () {
      expect(parsePairingPayload('{"v":2,"host":"10.0.0.5","port":"3011"}'), isNull);
      expect(parsePairingPayload('{"host":"10.0.0.5","port":"3011"}'), isNull);
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
