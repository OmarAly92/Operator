import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';

PushStatus status({
  bool supported = true,
  bool granted = true,
  bool canAskAgain = true,
  bool registered = false,
}) => PushStatus(
  supported: supported,
  granted: granted,
  canAskAgain: canAskAgain,
  registered: registered,
);

ServerConfig config([String host = '192.168.1.5']) =>
    ServerConfig(host: host, httpPort: '3011', secure: false, password: 'secret12');

void main() {
  group('describePushToggle', () {
    test('is off and disabled while the status is still loading', () {
      final toggle = describePushToggle(null, config());

      expect(toggle.value, isFalse);
      expect(toggle.disabled, isTrue);
      expect(toggle.footer, 'Checking…');
    });

    test('is disabled on a simulator, where no token can be minted', () {
      final toggle = describePushToggle(status(supported: false), config());

      expect(toggle.disabled, isTrue);
      expect(toggle.footer, contains('physical device'));
    });

    test('is disabled with no server paired, since there is nothing to register with', () {
      final toggle = describePushToggle(status(registered: true), config(''));

      expect(toggle.value, isFalse);
      expect(toggle.disabled, isTrue);
      expect(toggle.footer, contains('Connect to your Operator server'));
    });

    test('reads on only when permission is granted and the device is registered', () {
      expect(describePushToggle(status(registered: true), config()).value, isTrue);
      expect(describePushToggle(status(), config()).value, isFalse);
      expect(describePushToggle(status(granted: false, registered: true), config()).value, isFalse);
    });

    test('stays interactive when granted but not yet registered', () {
      final toggle = describePushToggle(status(), config());

      expect(toggle.disabled, isFalse);
      expect(toggle.blocked, isFalse);
      expect(toggle.footer, contains("isn't registered"));
    });

    test('offers a normal turn-on when permission has not been asked for yet', () {
      final toggle = describePushToggle(status(granted: false), config());

      expect(toggle.disabled, isFalse);
      expect(toggle.blocked, isFalse);
    });

    test('marks a permanent denial as blocked but leaves the switch tappable', () {
      final toggle = describePushToggle(status(granted: false, canAskAgain: false), config());

      expect(toggle.blocked, isTrue);
      expect(toggle.disabled, isFalse);
      expect(toggle.footer, contains('system settings'));
    });

    test('reports blocked even if a stale registration is still held', () {
      final toggle = describePushToggle(
        status(granted: false, canAskAgain: false, registered: true),
        config(),
      );

      expect(toggle.value, isFalse);
      expect(toggle.blocked, isTrue);
    });
  });

  group('hasServer', () {
    test('treats a missing, empty or whitespace host as no server', () {
      expect(hasServer(null), isFalse);
      expect(hasServer(config('')), isFalse);
      expect(hasServer(config('   ')), isFalse);
    });

    test('treats a real host as a server', () {
      expect(hasServer(config()), isTrue);
    });
  });

  group('classifyServerFailure', () {
    test('reports unreachable when there was no answer at all', () {
      expect(classifyServerFailure(null), PushRegisterFailure.serverUnreachable);
      expect(
        classifyServerFailure(StatusCode.noInternetConnection),
        PushRegisterFailure.serverUnreachable,
      );
      expect(
        classifyServerFailure(StatusCode.connectionTimeout),
        PushRegisterFailure.serverUnreachable,
      );
    });

    test('separates auth rejection, rate limiting and other error statuses', () {
      expect(classifyServerFailure(401), PushRegisterFailure.serverAuth);
      expect(classifyServerFailure(403), PushRegisterFailure.serverAuth);
      expect(classifyServerFailure(429), PushRegisterFailure.serverRateLimited);
      expect(classifyServerFailure(500), PushRegisterFailure.serverError);
      expect(classifyServerFailure(404), PushRegisterFailure.serverError);
    });
  });

  group('describeRegisterFailure', () {
    test('blames the server, not the build, when the daemon is unreachable', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.serverUnreachable,
        TargetPlatform.iOS,
      );

      expect(described.title, contains("Couldn't reach your Operator server"));
      expect('${described.title} ${described.message}', isNot(contains('entitlement')));
    });

    test('explains the missing entitlement only when the token itself failed on iOS', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.tokenFailed,
        TargetPlatform.iOS,
      );

      expect(described.message, contains('entitlement'));
      expect(described.message, contains('TestFlight'));
    });

    test('does not mention iOS entitlements on Android', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.tokenFailed,
        TargetPlatform.android,
      );

      expect(described.message, isNot(contains('entitlement')));
    });

    test('points at system settings when permission was denied', () {
      expect(
        describeRegisterFailure(PushRegisterFailure.denied, TargetPlatform.iOS).message,
        contains('system settings'),
      );
    });

    test('does not claim the server was unreachable when it answered and rejected us', () {
      for (final reason in [
        PushRegisterFailure.serverAuth,
        PushRegisterFailure.serverRateLimited,
        PushRegisterFailure.serverError,
      ]) {
        final described = describeRegisterFailure(reason, TargetPlatform.iOS);
        expect('${described.title} ${described.message}', isNot(contains("Couldn't reach")));
      }
    });

    test('points at the password when the server rejected the credentials', () {
      expect(
        describeRegisterFailure(PushRegisterFailure.serverAuth, TargetPlatform.iOS).message,
        contains('password'),
      );
    });

    test('names the HTTP status when the server errored, and omits it when unknown', () {
      expect(
        describeRegisterFailure(
          PushRegisterFailure.serverError,
          TargetPlatform.iOS,
          statusCode: 500,
        ).message,
        contains('HTTP 500'),
      );
      expect(
        describeRegisterFailure(PushRegisterFailure.serverError, TargetPlatform.iOS).message,
        isNot(contains('HTTP')),
      );
    });

    test('tells an unpaired user to connect rather than blaming the build or network', () {
      final described = describeRegisterFailure(
        PushRegisterFailure.notPaired,
        TargetPlatform.iOS,
      );

      expect(described.title, contains('Connect to your Operator server'));
      expect('${described.title} ${described.message}', isNot(contains('entitlement')));
      expect('${described.title} ${described.message}', isNot(contains("couldn't reach")));
    });

    test('covers the remaining reasons with a usable message', () {
      for (final reason in [PushRegisterFailure.notConfigured, PushRegisterFailure.unsupported]) {
        final described = describeRegisterFailure(reason, TargetPlatform.iOS);
        expect(described.title, isNotEmpty);
        expect(described.message, isNotEmpty);
      }
    });
  });
}
