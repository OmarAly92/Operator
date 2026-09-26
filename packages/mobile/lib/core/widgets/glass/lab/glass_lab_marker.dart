import 'package:flutter/widgets.dart';

class GlassLabMarker extends StatelessWidget {
  const GlassLabMarker(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(identifier: id, label: id, container: true, child: child);
}

class GlassLabReady extends StatelessWidget {
  const GlassLabReady({super.key});

  @override
  Widget build(BuildContext context) => const GlassLabMarker('scene.ready', child: SizedBox(width: 1, height: 1));
}
