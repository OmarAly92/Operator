sealed class PropRule {
  const PropRule();
}

final class OneOfRule extends PropRule {
  const OneOfRule(this.values);

  final List<String> values;
}

final class FlagRule extends PropRule {
  const FlagRule();
}

final class CountRule extends PropRule {
  const CountRule();
}

sealed class MobileEvents {
  static const String active = 'opr.v2.app.active';
  static const String paired = 'opr.v2.mobile_app.paired';
  static const String connected = 'opr.v2.mobile_app.connected';
  static const String onboardingStarted = 'opr.v2.mobile_app.onboarding_started';
  static const String onboardingCompleted = 'opr.v2.mobile_app.onboarding_completed';
  static const String onboardingSkipped = 'opr.v2.mobile_app.onboarding_skipped';
  static const String notificationOpened = 'opr.v2.mobile_app.notification_opened';
  static const String featureUsed = 'opr.v2.mobile_app.feature_used';

  static const Map<String, Map<String, PropRule>> allowlist = {
    active: {},
    paired: {
      'method': OneOfRule(['qr', 'manual']),
      'from_onboarding': FlagRule(),
    },
    connected: {
      'trigger': OneOfRule(['launch', 'reconnect']),
    },
    onboardingStarted: {},
    onboardingCompleted: {},
    onboardingSkipped: {},
    notificationOpened: {
      'target': OneOfRule(['session', 'prs']),
      'cold_start': FlagRule(),
    },
    featureUsed: {
      'feature': OneOfRule(['spawn', 'merge', 'kill', 'restore', 'conductor', 'send']),
      'outcome': OneOfRule(['succeeded', 'failed']),
    },
  };
}
