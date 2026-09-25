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

    test('labels the agent alert types', () {
      expect(notificationVisual(skin, 'turn_finished').label, 'Finished');
      expect(notificationVisual(skin, 'turn_finished').color, skin.green);
      expect(notificationVisual(skin, 'agent_exited').label, 'Exited');
      expect(notificationVisual(skin, 'agent_exited').color, skin.red);
    });
  });

  group('notificationTarget', () {
    test('opens the session for a needs_input notification', () {
      expect(notificationTarget(type: 'needs_input', sessionId: 'abc'), '/session/abc');
    });

    test('opens the session for turn_finished and agent_exited notifications', () {
      expect(notificationTarget(type: 'turn_finished', sessionId: 's1'), '/session/s1');
      expect(notificationTarget(type: 'agent_exited', sessionId: 's1'), '/session/s1');
      expect(notificationTarget(type: 'ready_to_merge', sessionId: 's1'), '/prs');
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

  group('plainPreview', () {
    test('strips bold, code and headings to plain text', () {
      expect(plainPreview('## Done\nWrote **`spec.md`** and ran `flutter test`.'), 'Done Wrote spec.md and ran flutter test.');
    });

    test('keeps link and image text and drops the target', () {
      expect(plainPreview('See [the PR](https://x.test/1) ![shot](a.png)'), 'See the PR shot');
    });

    test('drops quote, list and fence markers and folds lines', () {
      expect(plainPreview('> quoted\n- one\n2. two\n```dart\ncode\n```'), 'quoted one two code');
    });

    test('unwraps emphasis and strikethrough without eating snake_case or lone stars', () {
      expect(plainPreview('*really* ~~old~~ keep_this_name and 2 * 3'), 'really old keep_this_name and 2 * 3');
    });

    test('keeps underscores inside words', () {
      expect(plainPreview('Edited __init__.py and snake__case'), 'Edited __init__.py and snake__case');
    });

    test('still unwraps __bold__ that stands on its own', () {
      expect(plainPreview('This is __done__ now'), 'This is done now');
    });

    test('drops an unmatched leading **', () {
      expect(plainPreview('**Committed as 5b907f4. The ticket is complete'), 'Committed as 5b907f4. The ticket is complete');
    });

    test('drops an unmatched trailing ** left by truncation', () {
      expect(plainPreview('Wrote the spec to **spec'), 'Wrote the spec to spec');
    });

    test('a heading needs a space after the hashes', () {
      expect(plainPreview('#123 was fixed'), '#123 was fixed');
      expect(plainPreview('# Summary'), 'Summary');
    });

    test('a link target may contain parentheses', () {
      expect(plainPreview('See [the docs](https://x.test/a_(b)) now'), 'See the docs now');
    });

    test('leaves plain text alone', () {
      expect(plainPreview('Improve code finished its turn.'), 'Improve code finished its turn.');
    });
  });
}
