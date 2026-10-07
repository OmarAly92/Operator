import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';

@internal
abstract interface class GlassShapeMotion implements Listenable {
  Rect resolve(RenderBox shape);

  GlassUnionOutline? union(RenderBox shape);

  bool get isTransient;
}

@internal
@immutable
class GlassUnionOutline {
  const GlassUnionOutline({required this.rect, required this.shape, required this.leads});

  final Rect rect;
  final LiquidShape shape;
  final bool leads;

  GlassUnionOutline shift(Offset offset) => GlassUnionOutline(rect: rect.shift(offset), shape: shape, leads: leads);

  @override
  bool operator ==(Object other) => other is GlassUnionOutline && other.rect == rect && other.shape == shape && other.leads == leads;

  @override
  int get hashCode => Object.hash(rect, shape, leads);

  @override
  String toString() => 'GlassUnionOutline($rect, $shape, leads: $leads)';
}
