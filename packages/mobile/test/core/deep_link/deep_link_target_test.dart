import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

void main() {
  test('opens a session from the scheme, host-form and path-form alike', () {
    for (final link in ['aomobile://session/abc', 'aomobile:///session/abc']) {
      final target = resolveDeepLink(Uri.parse(link));

      expect(target?.route, RoutesStrings.session);
      expect(target?.arguments, {'sessionId': 'abc'});
    }
  });

  test('decodes a session id that needed escaping', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://session/a%20b'))?.arguments?['sessionId'],
      'a b',
    );
  });

  test('sends prs to the board with the PRs tab selected', () {
    final target = resolveDeepLink(Uri.parse('aomobile://prs'));

    expect(target?.route, RoutesStrings.sessions);
    expect(target?.tabIndex, 2);
  });

  test('opens the notification history', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://notifications'))?.route,
      RoutesStrings.notifications,
    );
  });

  test('opens a TUI session straight into the terminal', () {
    final target = resolveDeepLink(Uri.parse('aomobile://terminal/abc'));

    expect(target?.route, RoutesStrings.terminal);
    final args = target?.arguments?['args'] as TerminalArgs?;
    expect(args?.id, 'abc');
    expect(args?.sessionId, 'abc');
    expect(args?.shellOnly, isFalse);
  });

  test('refuses a link from another scheme', () {
    expect(resolveDeepLink(Uri.parse('https://example.com/session/abc')), isNull);
  });

  test('refuses a route it does not know, and a session with no id', () {
    expect(resolveDeepLink(Uri.parse('aomobile://settings')), isNull);
    expect(resolveDeepLink(Uri.parse('aomobile://session')), isNull);
    expect(resolveDeepLink(Uri.parse('aomobile://')), isNull);
  });

  test('resolves the internal paths notificationTarget produces', () {
    expect(resolveDeepLinkPath('/session/abc')?.arguments, {'sessionId': 'abc'});
    expect(resolveDeepLinkPath('/prs')?.tabIndex, 2);
    expect(resolveDeepLinkPath('nonsense'), isNull);
  });

  // Uri already decoded these segments; decoding them a second time turned a
  // legitimately escaped id into a different one.
  test('does not decode a parsed link twice', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://session/a%2525'))?.arguments,
      {'sessionId': 'a%25'},
    );
    expect(
      resolveDeepLink(Uri.parse('aomobile:///session/a%2Fb'))?.arguments,
      {'sessionId': 'a/b'},
    );
  });

  // A crafted link used to throw ArgumentError out of the link-stream listener.
  test('survives a truncated escape from either direction', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile:///session/a%252'))?.arguments,
      {'sessionId': 'a%2'},
    );
    expect(resolveDeepLinkPath('/session/a%2'), isNull);
    expect(resolveDeepLinkPath('/session/100%'), isNull);
  });

  test('round-trips an id that notificationTarget had to escape', () {
    expect(resolveDeepLinkPath('/session/a%20b')?.arguments, {'sessionId': 'a b'});
  });

  test('is equal for equal links, so a repeated cold-start link is detectable', () {
    expect(
      resolveDeepLink(Uri.parse('aomobile://session/abc')),
      resolveDeepLink(Uri.parse('aomobile://session/abc')),
    );
  });
}
