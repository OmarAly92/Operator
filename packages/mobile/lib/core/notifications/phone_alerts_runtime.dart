import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/mux_notification.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/viewed_session.dart';
import 'package:operator_mobile/feature/notification/logic/notification_view.dart';

const int _idMask = 0x7fffffff;

class PhoneAlertsRuntime {
  PhoneAlertsRuntime(this._mux, this._sink, this._openLink, {DateTime Function()? now})
    : _nextId = (now ?? DateTime.now)().millisecondsSinceEpoch & _idMask;

  final MuxClient _mux;
  final LocalAlertSink _sink;
  final bool Function(Uri uri) _openLink;
  StreamSubscription<MuxNotification>? _subscription;
  int _nextId;
  bool _canShow = false;
  bool _background = false;
  bool _subscribed = false;

  Future<void> start() async {
    if (_subscription != null) return;
    final bool canShow;
    try {
      canShow = await _sink.init((payload) => _openLink(Uri.parse(payload)));
    } on Object {
      return;
    }
    _subscription ??= _mux.notifications.listen(_onNotification);
    _canShow = canShow;
    _sync();
  }

  void foreground() {
    _background = false;
    _sync();
  }

  void background() {
    _background = true;
    _sync();
  }

  void _sync() {
    final want = _canShow && !_background;
    if (want == _subscribed) return;
    _subscribed = want;
    if (want) {
      _mux.subscribeNotifications();
    } else {
      _mux.unsubscribeNotifications();
    }
  }

  void _onNotification(MuxNotification n) {
    if (n.quiet || n.sessionId.isEmpty) return;
    if (ViewedSession.current.value == n.sessionId) return;
    final id = _nextId;
    _nextId = (_nextId + 1) & _idMask;
    unawaited(
      _sink.show(
        id: id,
        title: n.title,
        body: n.body,
        payload: '$kDeepLinkScheme:/${notificationTarget(type: n.type, sessionId: n.sessionId)}',
      ),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

AppLifecycleListener phoneAlertsLifecycle(PhoneAlertsRuntime Function() runtime, {VoidCallback? onResume}) =>
    AppLifecycleListener(
      onResume: () {
        onResume?.call();
        runtime().foreground();
      },
      onShow: () => runtime().foreground(),
      onHide: () => runtime().background(),
      onPause: () => runtime().background(),
    );
