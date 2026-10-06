import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_launch.dart';
import 'lab_parts.dart';

sealed class MotionScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'material.materialize': (launch) => MaterializeScene(backdrop: launch.backdrop),
    'material.materialize.snappy': (launch) => MaterializeScene(backdrop: launch.backdrop, animation: GlassAnimation.snappy),
    'material.materialize.bouncy': (launch) => MaterializeScene(backdrop: launch.backdrop, animation: GlassAnimation.bouncy),
  };

  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {
    'tool.visibility': (launch) => VisibilityScene(backdrop: launch.backdrop, visibility: launch.visibility ?? 1, blurRamp: launch.blurRamp ?? 1),
    'tool.ghost': (launch) => MaterializeScene(backdrop: launch.backdrop, label: 'Glass'),
    'tool.ghost.standalone': (launch) => MaterializeScene(backdrop: launch.backdrop, label: 'Glass', standalone: true),
    'tool.materialize.cold': (launch) => MaterializeScene(backdrop: launch.backdrop, warmUp: false),
  };
}

class MaterializeScene extends StatefulWidget {
  const MaterializeScene({super.key, required this.backdrop, this.animation, this.label, this.standalone = false, this.warmUp = true});

  final String backdrop;
  final GlassAnimation? animation;
  final String? label;
  final bool standalone;
  final bool warmUp;

  @override
  State<MaterializeScene> createState() => _MaterializeSceneState();
}

class _MaterializeSceneState extends State<MaterializeScene> {
  static const GlassAnimation warmUp = GlassAnimation.dampedSpring(response: 0.08, dampingFraction: 1);
  static const Duration warmUpStep = Duration(milliseconds: 150);

  bool _shown = true;

  @override
  void initState() {
    super.initState();
    if (widget.warmUp) WidgetsBinding.instance.addPostFrameCallback((_) => _warmUp());
  }

  Future<void> _warmUp() async {
    for (final shown in [false, true]) {
      if (!mounted) return;
      withGlassAnimation(warmUp, () => setState(() => _shown = shown));
      await Future<void>.delayed(warmUpStep);
    }
  }

  void _toggle() {
    final animation = widget.animation;
    if (animation == null) {
      setState(() => _shown = !_shown);
    } else {
      withGlassAnimation(animation, () => setState(() => _shown = !_shown));
    }
  }

  Widget _block() {
    final label = widget.label;
    if (label == null) return const LabBlock(width: 250, height: 88);
    return GlassEffect(
      child: SizedBox(
        width: 250,
        height: 88,
        child: GlassForeground(child: Center(child: Text(label, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LabCentered(
      backdrop: widget.backdrop,
      bottom: LabButton(title: 'Toggle', id: 'toggle', onTap: _toggle),
      children: [
        if (widget.standalone)
          SizedBox(width: 250, height: 88, child: _shown ? _block() : null)
        else
          GlassEffectContainer(child: _shown ? _block() : const SizedBox.shrink()),
      ],
    );
  }
}

class VisibilityScene extends StatelessWidget {
  const VisibilityScene({super.key, required this.backdrop, required this.visibility, this.blurRamp = 1});

  final String backdrop;
  final double visibility;
  final double blurRamp;

  @override
  Widget build(BuildContext context) {
    final material = GlassMaterial.resolve(
      glass: Glass.regular,
      shorterSide: 88,
      brightness: GlassTheme.brightnessOf(context),
      accessibility: GlassAccessibility.of(context),
    );
    final settings = material.toSettings().atVisibility(visibility, blurRampExponent: blurRamp);
    return LabCentered(
      backdrop: backdrop,
      children: [
        LiquidGlass.withOwnLayer(
          settings: settings,
          shape: const LiquidRoundedRectangle(borderRadius: 999),
          shadows: material.shadows,
          child: const SizedBox(width: 250, height: 88),
        ),
      ],
    );
  }
}
