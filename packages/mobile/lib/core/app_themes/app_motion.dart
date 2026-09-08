import 'package:flutter/animation.dart';

/// Motion constants extracted from the design prototype
/// (`docs/design/motion.md`). No ad-hoc [Duration]/[Curve] values outside
/// this class.
sealed class AppMotion {
  // ---------------------------------------------------------------------
  // Durations
  // ---------------------------------------------------------------------

  /// Press feedback, toggle thumb slide, translate-x chat bubble state swap.
  static const Duration fast = Duration(milliseconds: 120);

  /// Sheet/scrim/dialog/toast base transition speed; row hover/expand.
  static const Duration base = Duration(milliseconds: 180);

  /// Entrance stagger duration (fade-up/pop/slide-up), sheet/dialog pop-in.
  static const Duration slow = Duration(milliseconds: 260);

  /// Skeleton shimmer sweep.
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// Expressive loader shape-morph container spin.
  static const Duration loaderSpin = Duration(milliseconds: 1730);

  /// Expressive loader per-shape pop pulse.
  static const Duration loaderPop = Duration(milliseconds: 650);

  /// Typing/status dot bounce, one full cycle.
  static const Duration dotBounce = Duration(milliseconds: 1200);

  /// Per-dot stagger offset within [dotBounce].
  static const Duration dotBounceStagger = Duration(milliseconds: 150);

  /// Status dot "breathing" opacity pulse — active/busy state.
  static const Duration breatheActive = Duration(milliseconds: 1600);

  /// Status dot "breathing" opacity pulse — idle/stopped state.
  static const Duration breatheIdle = Duration(milliseconds: 2200);

  /// Empty-state orb float bob.
  static const Duration orbFloat = Duration(milliseconds: 2500);

  /// Plain busy/sending icon spinner.
  static const Duration spin = Duration(milliseconds: 1000);

  /// Base delay before the first item in a staggered entrance list appears.
  static const Duration staggerBase = Duration(milliseconds: 120);

  /// Additional delay per subsequent item in a staggered entrance list.
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// Entrance delay for the [index]-th item (0-based) in a staggered list,
  /// i.e. [staggerBase] + [index] * [staggerStep].
  static Duration staggerDelay(int index) =>
      staggerBase + staggerStep * index;

  // ---------------------------------------------------------------------
  // Curves
  //
  // Flutter's [Cubic] takes the same 4 control-point values as CSS
  // `cubic-bezier(x1, y1, x2, y2)` — a direct 1:1 mapping.
  // ---------------------------------------------------------------------

  /// `cubic-bezier(.22,.61,.36,1)` — default deceleration for entrances,
  /// scrims, and most one-shot transitions.
  static const Curve easeOut = Cubic(0.22, 0.61, 0.36, 1);

  /// `cubic-bezier(.65,0,.35,1)` — symmetric ease for looping animations
  /// (dot bounce, orb float).
  static const Curve easeInOut = Cubic(0.65, 0, 0.35, 1);

  /// `cubic-bezier(.34,1.4,.64,1)` — overshoot spring used for press
  /// feedback, sheet/dialog pop-in and slide-up, and the toggle thumb.
  /// The `1.4` second control point is what produces the overshoot.
  static const Curve spring = Cubic(0.34, 1.4, 0.64, 1);

  // ---------------------------------------------------------------------
  // Keyframe deltas
  // ---------------------------------------------------------------------

  /// `saFadeUp` translateY start offset (logical px); animates to 0.
  static const double fadeUpOffset = 10;

  /// `saPop` scale start value; animates to 1.
  static const double popScaleStart = 0.94;

  /// `saSlideUp` translateY start offset (logical px); animates to 0.
  static const double slideUpOffset = 60;

  /// `saLoaderPop` peak scale, reached at 77% of [loaderPop]'s cycle
  /// (holds at 1.0 from 0%-46%, peaks at 77%, returns to 1.0 by 100%).
  static const double loaderPopPeakScale = 1.125;

  /// `saDotBounce` translateY peak offset (logical px) at 30% of the cycle.
  static const double dotBounceOffset = -4;

  /// `saOrbFloat` translateY peak offset (logical px) at 50% of the cycle.
  static const double orbFloatOffset = -10;

  // ---------------------------------------------------------------------
  // Press scales (style-active — scale applied on press-down)
  // ---------------------------------------------------------------------

  /// Primary/secondary buttons, session cards (active + muted/archived),
  /// spawn submit/save buttons.
  static const double pressScaleDefault = 0.97;

  /// The floating "spawn agent" FAB.
  static const double pressScaleFab = 0.94;

  /// The chat composer send button.
  static const double pressScaleSend = 0.92;
}
