import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum GlassKind { regular, clear, identity }

@immutable
class Glass {
  const Glass._(this.kind, {this.tintColor, this.isInteractive = false});

  static const Glass regular = Glass._(GlassKind.regular);
  static const Glass clear = Glass._(GlassKind.clear);
  static const Glass identity = Glass._(GlassKind.identity);

  final GlassKind kind;
  final Color? tintColor;
  final bool isInteractive;

  Glass tint(Color? color) => Glass._(kind, tintColor: color, isInteractive: isInteractive);

  Glass interactive([bool enabled = true]) => Glass._(kind, tintColor: tintColor, isInteractive: enabled);

  bool sameMaterial(Glass other) => other.kind == kind && other.tintColor == tintColor;

  @override
  bool operator ==(Object other) =>
      other is Glass && other.kind == kind && other.tintColor == tintColor && other.isInteractive == isInteractive;

  @override
  int get hashCode => Object.hash(kind, tintColor, isInteractive);
}
