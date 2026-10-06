import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  const accent = Color(0xFF1ACB64);

  test('variants are distinct values', () {
    expect(Glass.regular.kind, GlassKind.regular);
    expect(Glass.clear.kind, GlassKind.clear);
    expect(Glass.identity.kind, GlassKind.identity);
    expect(Glass.regular, isNot(Glass.clear));
  });

  test('tint and interactive build equal values from equal inputs', () {
    expect(Glass.regular.tint(accent), Glass.regular.tint(accent));
    expect(Glass.regular.tint(accent).hashCode, Glass.regular.tint(accent).hashCode);
    expect(Glass.regular.tint(accent), isNot(Glass.regular));
    expect(Glass.regular.interactive(), isNot(Glass.regular));
    expect(Glass.regular.interactive().interactive(false), Glass.regular);
  });

  test('modifiers keep each other', () {
    final glass = Glass.clear.tint(accent).interactive();
    expect(glass.kind, GlassKind.clear);
    expect(glass.tintColor, accent);
    expect(glass.isInteractive, isTrue);
    expect(glass.tint(null).isInteractive, isTrue);
  });
}
