import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_marker.dart';
import 'lab_parts.dart';

class MorphScene extends StatefulWidget {
  const MorphScene({super.key, required this.backdrop, this.interactive = true, this.warmUp = true});

  static const List<(String, IconData)> badges = [('star.fill', Icons.star), ('heart.fill', Icons.favorite), ('bolt.fill', Icons.bolt)];
  static const double side = 56;
  static const double gap = 16;
  static const double spacing = 20;
  static const double iconSize = 22;

  final String backdrop;
  final bool interactive;
  final bool warmUp;

  @override
  State<MorphScene> createState() => _MorphSceneState();
}

class _MorphSceneState extends State<MorphScene> {
  static const GlassAnimation warmUp = GlassAnimation.dampedSpring(response: 0.08, dampingFraction: 1);
  static const Duration warmUpStep = Duration(milliseconds: 150);

  final GlassNamespace _namespace = GlassNamespace();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.warmUp) WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
  }

  Future<void> _warmUp() async {
    for (final expanded in [true, false]) {
      if (!mounted) return;
      withGlassAnimation(warmUp, () => setState(() => _expanded = expanded));
      await Future<void>.delayed(warmUpStep);
    }
  }

  void _toggle() => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => _expanded = !_expanded));

  @override
  Widget build(BuildContext context) {
    return LabCentered(
      backdrop: widget.backdrop,
      children: [
        GlassEffectContainer(
          spacing: MorphScene.spacing,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: MorphScene.gap,
            children: [
              if (_expanded)
                for (final (symbol, icon) in MorphScene.badges)
                  GlassEffect(
                    key: ValueKey(symbol),
                    id: GlassEffectID(symbol, _namespace),
                    child: SizedBox.square(dimension: MorphScene.side, child: GlassForeground(child: Icon(icon, size: MorphScene.iconSize))),
                  ),
              GlassLabMarker(
                'morph',
                key: const ValueKey('toggle'),
                child: GlassEffect(
                  glass: widget.interactive ? Glass.regular.interactive() : Glass.regular,
                  id: GlassEffectID('toggle', _namespace),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: SizedBox.square(
                      dimension: MorphScene.side,
                      child: GlassForeground(child: Icon(_expanded ? Icons.close : Icons.add, size: MorphScene.iconSize)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TapScene extends StatelessWidget {
  const TapScene({super.key, required this.backdrop});

  final String backdrop;

  @override
  Widget build(BuildContext context) {
    return LabCentered(
      backdrop: backdrop,
      children: [
        GlassEffectContainer(
          spacing: MorphScene.spacing,
          child: GlassLabMarker(
            'glass',
            child: GlassEffect(
              glass: Glass.regular.interactive(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox.square(dimension: MorphScene.side, child: GlassForeground(child: Icon(Icons.add, size: MorphScene.iconSize))),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
