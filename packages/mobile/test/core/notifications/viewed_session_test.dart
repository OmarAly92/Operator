import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

Widget _app(GlobalKey<NavigatorState> navigator, String sessionId) => MaterialApp(
  navigatorKey: navigator,
  home: ViewedSessionMarker(sessionId: sessionId, child: Text(sessionId)),
);

void _push(GlobalKey<NavigatorState> navigator, String sessionId) => navigator.currentState!.push(
  MaterialPageRoute<void>(builder: (_) => ViewedSessionMarker(sessionId: sessionId, child: Text(sessionId))),
);

void main() {
  setUp(ViewedSession.reset);
  tearDown(ViewedSession.reset);

  testWidgets('a marker sets the viewed session and clears it when it goes away', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, 's1'));
    expect(ViewedSession.current.value, 's1');

    await tester.pumpWidget(const SizedBox());
    expect(ViewedSession.current.value, isNull);
  });

  testWidgets('pushing s2 over s1 and popping leaves s1 viewed', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, 's1'));
    _push(navigator, 's2');
    await tester.pumpAndSettle();
    expect(ViewedSession.current.value, 's2');

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ViewedSession.current.value, 's1');
  });

  testWidgets('a marker whose session changes moves the viewed session with it', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, 's1'));
    await tester.pumpWidget(_app(navigator, 's3'));
    expect(ViewedSession.current.value, 's3');
  });

  test('an empty session id marks nothing', () {
    final owner = Object();
    ViewedSession.show(owner, '');
    expect(ViewedSession.current.value, isNull);
  });

  test('removal is by owner, not by session id', () {
    final a = Object();
    final b = Object();
    ViewedSession.show(a, 's1');
    ViewedSession.show(b, 's1');
    ViewedSession.hide(b);
    expect(ViewedSession.current.value, 's1');
    ViewedSession.hide(a);
    expect(ViewedSession.current.value, isNull);
  });
}
