import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';

void main() {
  group('classifyConnectionFailure', () {
    test('treats no answer as unreachable', () {
      expect(classifyConnectionFailure(null), ConnectionFailure.unreachable);
    });

    test('maps 401 and 403 to auth', () {
      expect(classifyConnectionFailure(401), ConnectionFailure.auth);
      expect(classifyConnectionFailure(403), ConnectionFailure.auth);
    });

    test('maps 429 to rateLimited', () {
      expect(classifyConnectionFailure(429), ConnectionFailure.rateLimited);
    });

    test('maps any other status to serverError', () {
      expect(classifyConnectionFailure(500), ConnectionFailure.serverError);
      expect(classifyConnectionFailure(404), ConnectionFailure.serverError);
    });
  });

  group('isLocalNetworkHost', () {
    test('accepts the RFC1918 ranges', () {
      expect(isLocalNetworkHost('10.0.0.4'), isTrue);
      expect(isLocalNetworkHost('192.168.1.5'), isTrue);
      expect(isLocalNetworkHost('172.16.0.1'), isTrue);
      expect(isLocalNetworkHost('172.31.255.254'), isTrue);
    });

    test('rejects addresses just outside the 172.16/12 block', () {
      expect(isLocalNetworkHost('172.15.0.1'), isFalse);
      expect(isLocalNetworkHost('172.32.0.1'), isFalse);
    });

    test('accepts loopback, link-local, and mDNS names', () {
      expect(isLocalNetworkHost('127.0.0.1'), isTrue);
      expect(isLocalNetworkHost('169.254.1.1'), isTrue);
      expect(isLocalNetworkHost('localhost'), isTrue);
      expect(isLocalNetworkHost('my-pc.local'), isTrue);
    });

    test('rejects the Tailscale CGNAT range and public hosts', () {
      expect(isLocalNetworkHost('100.101.102.103'), isFalse);
      expect(isLocalNetworkHost('my-pc.tail1234.ts.net'), isFalse);
      expect(isLocalNetworkHost('203.0.113.7'), isFalse);
    });

    test('ignores surrounding whitespace and case', () {
      expect(isLocalNetworkHost('  My-PC.Local  '), isTrue);
    });

    test('rejects an empty host', () {
      expect(isLocalNetworkHost(''), isFalse);
      expect(isLocalNetworkHost('   '), isFalse);
    });
  });

  group('describeConnectionFailure', () {
    test('names the scanned address when nothing answered', () {
      final d = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: '192.168.1.5',
        port: '3011',
        platform: TargetPlatform.iOS,
      );
      expect(d.message, contains('192.168.1.5:3011'));
      expect(d.message, contains('same Wi-Fi'));
    });

    test('blames the password, not the network, on auth', () {
      final d = describeConnectionFailure(
        ConnectionFailure.auth,
        host: '192.168.1.5',
        port: '3011',
        platform: TargetPlatform.iOS,
      );
      expect(d.message, contains('rotated'));
      expect(d.message, isNot(contains('Wi-Fi')));
      expect(d.showLocalNetworkHint, isFalse);
    });

    test('gives every cause a distinct, non-empty title', () {
      final titles = ConnectionFailure.values
          .map((r) => describeConnectionFailure(r, host: '192.168.1.5', port: '3011', platform: TargetPlatform.iOS).title)
          .toList();
      expect(titles.every((t) => t.isNotEmpty), isTrue);
      expect(titles.toSet().length, titles.length);
      expect(
        describeConnectionFailure(ConnectionFailure.auth, host: '', port: '', platform: TargetPlatform.iOS).title,
        isNot(contains('disconnected')),
      );
      expect(
        describeConnectionFailure(ConnectionFailure.unreachable, host: '', port: '', platform: TargetPlatform.iOS).title,
        contains('disconnected'),
      );
    });

    test('explains the lockout on rateLimited, and that it clears itself', () {
      final d = describeConnectionFailure(ConnectionFailure.rateLimited, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains('locked this device out'));
      expect(d.message, contains('about a minute'));
    });

    test('points at the desktop logs on a server error', () {
      final d = describeConnectionFailure(ConnectionFailure.serverError, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains('Operator logs'));
    });

    test('rejects a non-Operator QR code without mentioning the network', () {
      final d = describeConnectionFailure(ConnectionFailure.notOprQr, host: '', port: '', platform: TargetPlatform.iOS);
      expect(d.message, contains("isn't an Operator pairing code"));
      expect(d.showLocalNetworkHint, isFalse);
    });

    group('the iOS Local Network hint', () {
      test('shows for an unreachable LAN host on iOS', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isTrue);
      });

      test('does not show on Android, which has no such prompt', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.android,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });

      test('does not show for a Tailscale host', () {
        final d = describeConnectionFailure(
          ConnectionFailure.unreachable,
          host: '100.101.102.103',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });

      test('does not show when the server answered', () {
        final d = describeConnectionFailure(
          ConnectionFailure.auth,
          host: '192.168.1.5',
          port: '3011',
          platform: TargetPlatform.iOS,
        );
        expect(d.showLocalNetworkHint, isFalse);
      });
    });
  });

  group('shouldKeepPolling', () {
    test('stops on rejection', () {
      expect(shouldKeepPolling(401), isFalse);
      expect(shouldKeepPolling(403), isFalse);
      expect(shouldKeepPolling(429), isFalse);
    });

    test('keeps going on transient failures', () {
      expect(shouldKeepPolling(null), isTrue);
      expect(shouldKeepPolling(500), isTrue);
      expect(shouldKeepPolling(502), isTrue);
      expect(shouldKeepPolling(404), isTrue);
    });

    test('catches 403', () {
      expect(shouldKeepPolling(403), isFalse);
    });
  });
}
