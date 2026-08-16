import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:operator_mobile/core/api/server_config.dart';

class PushStatus extends Equatable {
  const PushStatus({
    required this.supported,
    required this.granted,
    required this.canAskAgain,
    required this.registered,
  });

  final bool supported;
  final bool granted;
  final bool canAskAgain;
  final bool registered;

  @override
  List<Object?> get props => [supported, granted, canAskAgain, registered];
}

class PushToggle extends Equatable {
  const PushToggle({
    required this.value,
    required this.disabled,
    required this.footer,
    required this.blocked,
  });

  final bool value;
  final bool disabled;
  final String footer;
  final bool blocked;

  @override
  List<Object?> get props => [value, disabled, footer, blocked];
}

enum PushRegisterFailure {
  unsupported,
  notPaired,
  notConfigured,
  denied,
  tokenFailed,
  serverUnreachable,
  serverAuth,
  serverRateLimited,
  serverError,
}

sealed class PushRegisterResult extends Equatable {
  const PushRegisterResult();
}

final class PushRegistered extends PushRegisterResult {
  const PushRegistered(this.token);

  final String token;

  @override
  List<Object?> get props => [token];
}

final class PushNotRegistered extends PushRegisterResult {
  const PushNotRegistered(this.reason, {this.statusCode});

  final PushRegisterFailure reason;
  final int? statusCode;

  @override
  List<Object?> get props => [reason, statusCode];
}

bool hasServer(ServerConfig? server) => (server?.host.trim() ?? '').isNotEmpty;

PushToggle describePushToggle(PushStatus? status, ServerConfig? server) {
  if (status == null) {
    return const PushToggle(value: false, disabled: true, footer: 'Checking…', blocked: false);
  }
  if (!status.supported) {
    return const PushToggle(
      value: false,
      disabled: true,
      footer: 'Push notifications need a physical device.',
      blocked: false,
    );
  }
  if (!hasServer(server)) {
    return const PushToggle(
      value: false,
      disabled: true,
      footer: 'Connect to your Operator server first — notifications turn on once connected.',
      blocked: false,
    );
  }
  if (!status.granted && !status.canAskAgain) {
    return const PushToggle(
      value: false,
      disabled: false,
      footer: 'Notifications are turned off for Operator in system settings.',
      blocked: true,
    );
  }
  if (status.granted && status.registered) {
    return const PushToggle(
      value: true,
      disabled: false,
      footer: "You'll be alerted when an agent needs you or a PR is ready.",
      blocked: false,
    );
  }
  if (status.granted) {
    return const PushToggle(
      value: false,
      disabled: false,
      footer: "This device isn't registered with your server yet.",
      blocked: false,
    );
  }
  return const PushToggle(
    value: false,
    disabled: false,
    footer: 'Turn on alerts for agents that need input and PR updates.',
    blocked: false,
  );
}

/// A negative status code is this app's marker for a request that never got an
/// answer (see `StatusCode`), which is what RN expressed as an absent status.
PushRegisterFailure classifyServerFailure(int? statusCode) {
  if (statusCode == null || statusCode < 0) return PushRegisterFailure.serverUnreachable;
  if (statusCode == 401 || statusCode == 403) return PushRegisterFailure.serverAuth;
  if (statusCode == 429) return PushRegisterFailure.serverRateLimited;
  return PushRegisterFailure.serverError;
}

({String title, String message}) describeRegisterFailure(
  PushRegisterFailure reason,
  TargetPlatform platform, {
  int? statusCode,
}) => switch (reason) {
  PushRegisterFailure.serverUnreachable => (
    title: "Couldn't reach your Operator server",
    message:
        'Your device is set up for notifications, but we could not reach your server to register '
        'it. Check that Operator is running and your phone is on the same network, then try again.',
  ),
  PushRegisterFailure.serverAuth => (
    title: 'Your Operator server rejected the request',
    message:
        'We reached your server, but it would not accept the connection password. Re-enter it '
        'under Settings → Connect Operator, then try again.',
  ),
  PushRegisterFailure.serverRateLimited => (
    title: 'Too many attempts',
    message:
        'Your Operator server is temporarily refusing new attempts. Wait a minute, then try again.',
  ),
  PushRegisterFailure.serverError => (
    title: "Your Operator server couldn't register this device",
    message:
        'We reached your server, but it returned an error'
        '${statusCode == null ? '' : ' (HTTP $statusCode)'}. '
        'Check the Operator logs on your computer, then try again.',
  ),
  PushRegisterFailure.notPaired => (
    title: 'Connect to your Operator server first',
    message:
        "This app isn't paired with a server yet, so there's nothing to register with. Pair with "
        'your server under Settings → Connect Operator — notifications turn on once connected.',
  ),
  PushRegisterFailure.tokenFailed => (
    title: "This build can't receive push notifications",
    message: platform == TargetPlatform.iOS
        ? 'This iOS build has no push entitlement. Install a build distributed through TestFlight '
              'to receive notifications.'
        : 'The device could not provide a push token for this build.',
  ),
  PushRegisterFailure.denied => (
    title: 'Notifications are turned off',
    message: 'Allow notifications for Operator in your system settings, then try again.',
  ),
  PushRegisterFailure.notConfigured => (
    title: "Push isn't configured in this build",
    message:
        'This build has no Firebase configuration, so it cannot register for notifications.',
  ),
  PushRegisterFailure.unsupported => (
    title: 'Not available on this device',
    message: 'Push notifications only work on a physical device, not a simulator.',
  ),
};
