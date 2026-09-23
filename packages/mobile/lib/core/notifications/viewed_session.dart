import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

sealed class ViewedSession {
  static final ValueNotifier<String?> _current = ValueNotifier<String?>(null);
  static final List<(Object, String)> _stack = [];

  static ValueListenable<String?> get current => _current;

  static void show(Object owner, String sessionId) {
    _stack.removeWhere((entry) => identical(entry.$1, owner));
    if (sessionId.isNotEmpty) _stack.add((owner, sessionId));
    _sync();
  }

  static void hide(Object owner) {
    _stack.removeWhere((entry) => identical(entry.$1, owner));
    _sync();
  }

  @visibleForTesting
  static void reset() {
    _stack.clear();
    _sync();
  }

  static void _sync() => _current.value = _stack.isEmpty ? null : _stack.last.$2;
}

class ViewedSessionMarker extends StatefulWidget {
  const ViewedSessionMarker({required this.sessionId, required this.child, super.key});

  final String sessionId;
  final Widget child;

  @override
  State<ViewedSessionMarker> createState() => _ViewedSessionMarkerState();
}

class _ViewedSessionMarkerState extends State<ViewedSessionMarker> {
  @override
  void initState() {
    super.initState();
    ViewedSession.show(this, widget.sessionId);
  }

  @override
  void didUpdateWidget(ViewedSessionMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) ViewedSession.show(this, widget.sessionId);
  }

  @override
  void dispose() {
    ViewedSession.hide(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
