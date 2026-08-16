import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';

const DarkSkin skin = DarkSkin();

void main() {
  group('notificationVisual', () {
    test('gives every known type its own label', () {
      final labels = ['needs_input', 'ready_to_merge', 'pr_merged', 'pr_closed_unmerged']
          .map((type) => notificationVisual(skin, type).label)
          .toSet();

      expect(labels, hasLength(4));
    });

    test('keeps the state hues meaningful', () {
      expect(notificationVisual(skin, 'needs_input').color, skin.amber);
      expect(notificationVisual(skin, 'ready_to_merge').color, skin.green);
      expect(notificationVisual(skin, 'pr_merged').color, skin.blue);
      expect(notificationVisual(skin, 'pr_closed_unmerged').color, skin.red);
    });

    test('falls back to a usable label for an unknown or empty type', () {
      expect(notificationVisual(skin, 'something_new').label, 'something_new');
      expect(notificationVisual(skin, '').label, 'Notification');
      expect(notificationVisual(skin, '').color, skin.textTertiary);
    });
  });

  group('notificationTarget', () {
    test('opens the session for a needs_input notification', () {
      expect(notificationTarget(type: 'needs_input', sessionId: 'abc'), '/session/abc');
    });

    test('falls back to the PRs tab when there is no session to open', () {
      expect(notificationTarget(type: 'needs_input', sessionId: ''), '/prs');
      expect(notificationTarget(type: 'needs_input'), '/prs');
    });

    test('sends PR notifications to the PRs tab', () {
      expect(notificationTarget(type: 'ready_to_merge', sessionId: 'abc'), '/prs');
      expect(notificationTarget(type: 'pr_merged', sessionId: 'abc'), '/prs');
    });

    test('sends an unknown or missing type to the PRs tab', () {
      expect(notificationTarget(type: ''), '/prs');
      expect(notificationTarget(type: '', sessionId: 'abc'), '/prs');
      expect(notificationTarget(type: 'something_new', sessionId: 'abc'), '/prs');
    });

    // The consumer decodes, so an id carrying a % or a / has to be escaped here
    // or it resolves to the wrong session — or to nothing at all.
    test('escapes an id the path would otherwise mangle', () {
      expect(notificationTarget(type: 'needs_input', sessionId: 'a/b'), '/session/a%2Fb');
      expect(notificationTarget(type: 'needs_input', sessionId: '100%'), '/session/100%25');
    });
  });

  group('relativeTime', () {
    final now = DateTime.utc(2026, 7, 30, 12);
    String ago(Duration age) => now.subtract(age).toIso8601String();

    test('collapses anything under a minute to now', () {
      expect(relativeTime(ago(const Duration(seconds: 5)), now), 'now');
    });

    test('steps through minutes, hours, days and weeks', () {
      expect(relativeTime(ago(const Duration(minutes: 3)), now), '3m');
      expect(relativeTime(ago(const Duration(hours: 4)), now), '4h');
      expect(relativeTime(ago(const Duration(days: 2)), now), '2d');
      expect(relativeTime(ago(const Duration(days: 20)), now), '2w');
    });

    test('does not render a negative age when the clocks disagree', () {
      expect(relativeTime(ago(const Duration(seconds: -30)), now), 'now');
    });

    test('returns nothing for an unparseable timestamp', () {
      expect(relativeTime('not-a-date', now), isEmpty);
    });
  });
}
