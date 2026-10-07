import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_launch.dart';
import 'lab_parts.dart';

sealed class SpacingScenes {
  static const Map<String, List<double>> gaps = {
    'material.spacing.default.a': [0, 4, 8, 12],
    'material.spacing.default.b': [16, 20, 24, 32],
    'material.spacing.default.c': [40, 48, 60],
    'material.spacing.40.a': [0, 4, 8, 12],
    'material.spacing.40.b': [16, 20, 24, 32],
    'material.spacing.40.c': [40, 48, 60],
    'material.spacing.4.a': [0, 4, 8, 12],
    'material.spacing.6.a': [0, 4, 8, 12],
    'material.spacing.8.a': [0, 4, 8, 12],
    'material.spacing.10.a': [0, 4, 8, 12],
    'material.spacing.12.a': [0, 4, 8, 12],
    'material.spacing.16.a': [0, 4, 8, 12],
    'material.spacing.20.a': [0, 4, 8, 12],
    'material.spacing.80.a': [0, 4, 8, 12],
    'material.spacing.default.d': [2, 5, 6, 7],
    'material.spacing.20.b': [9, 10, 11, 14],
    'material.spacing.20.c': [16, 18, 24, 32],
    'material.spacing.40.d': [18, 19, 21, 22],
    'material.spacing.40.e': [28, 36, 44, 52],
    'material.spacing.80.b': [16, 24, 32, 36],
    'material.spacing.80.c': [38, 40, 42, 44],
    'material.spacing.80.d': [48, 56, 64, 72],
    'material.spacing.80.e': [80, 88, 96],
  };

  static final Map<String, double?> spacing = {
    for (final id in gaps.keys) id: switch (id.split('.')[2]) {
      'default' => null,
      final value => double.parse(value),
    },
  };

  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    for (final MapEntry(key: id, value: gaps) in gaps.entries)
      id: (launch) => SpacingScene(backdrop: launch.backdrop, gaps: gaps, spacing: spacing[id]),
    'material.merge': (launch) => MergeScene(backdrop: launch.backdrop),
  };
}

class PixelCenter extends SingleChildLayoutDelegate {
  const PixelCenter(this.devicePixelRatio);

  final double devicePixelRatio;

  double _snap(double points) => (points * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(_snap((size.width - childSize.width) / 2), _snap((size.height - childSize.height) / 2));

  @override
  bool shouldRelayout(PixelCenter oldDelegate) => oldDelegate.devicePixelRatio != devicePixelRatio;
}

class SpacingPair extends StatelessWidget {
  const SpacingPair({super.key, required this.gap, this.spacing});

  final double gap;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final circles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
        SizedBox(width: gap),
        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
      ],
    );
    final spacing = this.spacing;
    return spacing == null ? GlassEffectContainer(child: circles) : GlassEffectContainer(spacing: spacing, child: circles);
  }
}

class SpacingScene extends StatelessWidget {
  const SpacingScene({super.key, required this.backdrop, required this.gaps, this.spacing});

  final String backdrop;
  final List<double> gaps;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: backdrop)),
        SafeArea(
          child: CustomSingleChildLayout(
            delegate: const WholePointCenter(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, gap) in gaps.indexed) ...[
                  if (index > 0) const SizedBox(height: 100),
                  SizedBox(
                    width: double.infinity,
                    height: 80,
                    child: CustomSingleChildLayout(delegate: PixelCenter(pixelRatio), child: SpacingPair(gap: gap, spacing: spacing)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MergeScene extends StatefulWidget {
  const MergeScene({super.key, required this.backdrop});

  final String backdrop;

  @override
  State<MergeScene> createState() => _MergeSceneState();
}

class _MergeSceneState extends State<MergeScene> {
  bool _merged = false;

  void _set(bool merged) => withGlassAnimation(GlassAnimation.defaultSpring, () => setState(() => _merged = merged));

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: widget.backdrop)),
        SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: const WholePointCenter(),
                  child: GlassEffectContainer(
                    spacing: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
                        SizedBox(width: _merged ? 0 : 80),
                        const LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 120,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LabButton(title: 'Merge', id: 'merge', onTap: () => _set(true)),
                      const SizedBox(width: 24),
                      LabButton(title: 'Split', id: 'split', onTap: () => _set(false)),
                    ],
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
