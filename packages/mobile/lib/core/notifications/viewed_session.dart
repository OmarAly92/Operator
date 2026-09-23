import 'package:flutter/widgets.dart';

sealed class ViewedSession {
  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);
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
    if (widget.sessionId.isNotEmpty) ViewedSession.current.value = widget.sessionId;
  }

  @override
  void dispose() {
    if (ViewedSession.current.value == widget.sessionId) ViewedSession.current.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
