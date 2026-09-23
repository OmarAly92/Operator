import 'dart:async';

import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';

class PhoneAlertsRuntime {
  PhoneAlertsRuntime(this._mux, this._sink, this._openLink);

  final MuxClient _mux;
  final LocalAlertSink _sink;
  final bool Function(Uri uri) _openLink;
  StreamSubscription<MuxNotification>? _subscription;
  int _nextId = 1;
  bool _background = false;

  Future<void> start() async {
    await _sink.init((payload) => _openLink(Uri.parse(payload)));
    _subscription ??= _mux.notifications.listen(_onNotification);
    if (!_background) _mux.subscribeNotifications();
  }

  void foreground() {
    _background = false;
    _mux.subscribeNotifications();
  }

  void background() {
    _background = true;
    _mux.unsubscribeNotifications();
  }

  void _onNotification(MuxNotification n) {
    if (n.quiet || n.sessionId.isEmpty) return;
    if (ViewedSession.current.value == n.sessionId) return;
    unawaited(
      _sink.show(
        id: _nextId++,
        title: n.title,
        body: n.body,
        payload: '$kDeepLinkScheme://session/${Uri.encodeComponent(n.sessionId)}',
      ),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
