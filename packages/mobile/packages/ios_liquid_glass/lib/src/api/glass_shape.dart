import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';

@immutable
sealed class GlassShape {
  const GlassShape();

  const factory GlassShape.capsule() = GlassCapsule;
  const factory GlassShape.circle() = GlassCircle;
  const factory GlassShape.rect(double cornerRadius) = GlassRect;
  const factory GlassShape.superellipse(double cornerRadius) = GlassSuperellipse;

  LiquidShape get liquidShape;

  ShapeBorder get border;
}

class GlassCapsule extends GlassShape {
  const GlassCapsule();

  @override
  LiquidShape get liquidShape => const LiquidRoundedRectangle(borderRadius: 999);

  @override
  ShapeBorder get border => const StadiumBorder();

  @override
  bool operator ==(Object other) => other is GlassCapsule;

  @override
  int get hashCode => (GlassCapsule).hashCode;
}

class GlassCircle extends GlassShape {
  const GlassCircle();

  @override
  LiquidShape get liquidShape => const LiquidOval();

  @override
  ShapeBorder get border => const CircleBorder();

  @override
  bool operator ==(Object other) => other is GlassCircle;

  @override
  int get hashCode => (GlassCircle).hashCode;
}

class GlassRect extends GlassShape {
  const GlassRect(this.cornerRadius);

  final double cornerRadius;

  @override
  LiquidShape get liquidShape => LiquidRoundedRectangle(borderRadius: cornerRadius);

  @override
  ShapeBorder get border => RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(cornerRadius)));

  @override
  bool operator ==(Object other) => other is GlassRect && other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(GlassRect, cornerRadius);
}

class GlassSuperellipse extends GlassShape {
  const GlassSuperellipse(this.cornerRadius);

  final double cornerRadius;

  @override
  LiquidShape get liquidShape => LiquidRoundedSuperellipse(borderRadius: cornerRadius);

  @override
  ShapeBorder get border => RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(cornerRadius)));

  @override
  bool operator ==(Object other) => other is GlassSuperellipse && other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(GlassSuperellipse, cornerRadius);
}
