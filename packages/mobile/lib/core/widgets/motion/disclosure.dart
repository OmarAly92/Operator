import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

class DisclosureChevron extends StatelessWidget {
  const DisclosureChevron({
    super.key,
    required this.expanded,
    this.size = 14,
    this.color,
    this.collapsedTurns = 0,
    this.expandedTurns = 0.25,
  });

  final bool expanded;
  final double size;
  final Color? color;
  final double collapsedTurns;
  final double expandedTurns;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedRotation(
      turns: expanded ? expandedTurns : collapsedTurns,
      duration: reduceMotion ? Duration.zero : AppMotion.disclosure,
      curve: AppMotion.easeOut,
      child: Icon(Icons.keyboard_arrow_down, size: size, color: color),
    );
  }
}

class Disclosure extends StatefulWidget {
  const Disclosure({super.key, required this.expanded, required this.child, this.initiallyExpanded});

  final bool expanded;
  final Widget child;
  final bool? initiallyExpanded;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> with SingleTickerProviderStateMixin {
  static final double _fadeInEnd = AppMotion.disclosureIn.inMicroseconds / AppMotion.disclosure.inMicroseconds;
  static final double _fadeOutStart = 1 - AppMotion.disclosureOut.inMicroseconds / AppMotion.disclosure.inMicroseconds;

  late final AnimationController _controller;
  late final Animation<double> _size;
  late final Animation<double> _fade;
  Widget? _retained;

  @override
  void initState() {
    super.initState();
    final initial = widget.initiallyExpanded ?? widget.expanded;
    _controller = AnimationController(vsync: this, duration: AppMotion.disclosure, value: initial ? 1 : 0)
      ..addStatusListener(_onStatus);
    _size = CurvedAnimation(parent: _controller, curve: AppMotion.easeOut, reverseCurve: AppMotion.easeOut.flipped);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, _fadeInEnd, curve: AppMotion.easeOut),
      reverseCurve: Interval(_fadeOutStart, 1, curve: AppMotion.easeOut.flipped),
    );
    if (initial != widget.expanded) _animateTo(widget.expanded);
  }

  void _animateTo(bool expanded) {
    if (expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _controller.isAnimating) {
      _controller.value = widget.expanded ? 1 : 0;
      _retained = null;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() => _retained = null);
  }

  @override
  void didUpdateWidget(covariant Disclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    _retained = widget.expanded ? null : oldWidget.child;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.expanded ? 1 : 0;
    } else {
      _animateTo(widget.expanded);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showChild = widget.expanded || !_controller.isDismissed;
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: showChild
            ? IgnorePointer(
                key: const ValueKey('expanded'),
                ignoring: !widget.expanded,
                child: widget.expanded ? widget.child : _retained ?? widget.child,
              )
            : const SizedBox.shrink(key: ValueKey('collapsed')),
      ),
    );
  }
}
