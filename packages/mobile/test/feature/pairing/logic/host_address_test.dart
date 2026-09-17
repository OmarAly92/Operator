import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pairing/logic/host_address.dart';

void main() {
  group('parseHostAddress', () {
    test('splits host and port', () {
      expect(parseHostAddress('192.168.1.2:58682'), const HostAddress(host: '192.168.1.2', port: '58682'));
    });

    test('defaults to the daemon port when none is given', () {
      expect(parseHostAddress('  192.168.1.2 '), const HostAddress(host: '192.168.1.2', port: '3011'));
    });

    test('reads the scheme and drops any path', () {
      expect(
        parseHostAddress('https://tunnel.ngrok-free.dev/'),
        const HostAddress(host: 'tunnel.ngrok-free.dev', port: '443', secure: true),
      );
      expect(
        parseHostAddress('http://10.0.0.5:3011/foo'),
        const HostAddress(host: '10.0.0.5', port: '3011', secure: false),
      );
    });

    test('handles bracketed IPv6 with and without a port', () {
      expect(parseHostAddress('[fe80::1]:3011'), const HostAddress(host: 'fe80::1', port: '3011'));
      expect(parseHostAddress('[fe80::1]'), const HostAddress(host: 'fe80::1', port: '3011'));
    });

    test('leaves a bare IPv6 address alone', () {
      expect(parseHostAddress('fe80::1'), const HostAddress(host: 'fe80::1', port: '3011'));
    });
  });

  group('formatHostAddress', () {
    test('omits the default port', () {
      expect(formatHostAddress('10.0.0.5', '3011'), '10.0.0.5');
      expect(formatHostAddress('10.0.0.5', '58682'), '10.0.0.5:58682');
    });
  });
}
