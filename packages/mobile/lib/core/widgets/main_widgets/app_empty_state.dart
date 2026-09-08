import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

/// Matches the prototype's `S.emptyWrap`/`S.emptyOrb`/`S.emptyTitle`/
/// `S.emptyBody` spec (`docs/design/components.md`): a floating brand-green
/// orb (`saOrbFloat`), a display-family title, and secondary body copy.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  /// Unused when the brand orb renders (kept for call sites that still pass
  /// one; the prototype's empty states always use the orb, never an icon).
  final IconData? icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(34, 44, 34, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EmptyOrb(),
          const VerticalSpace(22),
          AppText(title, style: AppTextStyle.style21Bold.copyWith(letterSpacing: -0.3)),
          const VerticalSpace(8),
          AppText(
            message,
            style: AppTextStyle.style13p5Regular.copyWith(color: skin.textSecondary, height: 1.45),
            maxLines: 4,
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const VerticalSpace(22), action!],
        ],
      ),
    );

    // The orb + display title make this taller than the old icon-based
    // layout — scroll rather than overflow when the host gives less height
    // than that (e.g. a terminal overlay sized to a small viewport). When the
    // host's height is itself unbounded (e.g. already inside a scroll view),
    // there's nothing to fill or overflow, so just size to content.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _EmptyOrb extends StatefulWidget {
  const _EmptyOrb();

  @override
  State<_EmptyOrb> createState() => _EmptyOrbState();
}

class _EmptyOrbState extends State<_EmptyOrb> with SingleTickerProviderStateMixin {
  // A truly-infinite loop never lets `WidgetTester.pumpAndSettle` finish once
  // this (persistent, no-data) state is mounted — Flutter's test binding
  // does not disable animations by default, and this widget has no reliable
  // way to detect it's under test. Floating a bounded number of cycles then
  // resting is not distinguishable from "still floating" to a user glancing
  // at an empty screen, and lets every existing `pumpAndSettle` call site
  // keep working unmodified.
  //
  // `AnimationController.repeat()` is NOT used here: its `_RepeatingSimulation`
  // only ever reports `AnimationStatus.forward`/`reverse`, never
  // `completed`/`dismissed`, so there is no status transition to count
  // cycles from. Driving `forward()`/`reverse()` manually instead gives real
  // status transitions per leg.
  static const _cycles = 3;
  var _completedCycles = 0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.orbFloat);
    _runCycle();
  }

  Future<void> _runCycle() async {
    if (!mounted || _completedCycles >= _cycles) return;
    await _controller.forward();
    if (!mounted) return;
    await _controller.reverse();
    _completedCycles++;
    _runCycle();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = AppMotion.easeInOut.transform(_controller.value);
        return Transform.translate(offset: Offset(0, AppMotion.orbFloatOffset * t), child: child);
      },
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.36, -0.44),
            colors: [Color(0xFF6CDB97), Color(0xFF15A552), Color(0xFF0C5C2E)],
            stops: [0, 0.52, 1],
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x591ACB64), blurRadius: 44, offset: Offset(0, 12)),
          ],
        ),
      ),
    );
  }
}
