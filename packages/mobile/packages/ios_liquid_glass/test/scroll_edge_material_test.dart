import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  test('rows resolve per style and appearance and take prefixed overrides', () {
    final soft = ScrollEdgeMaterial.resolve(style: ScrollEdgeStyle.soft, brightness: Brightness.dark);
    expect(soft['extent'], ios27ScrollEdgeTable['dark.soft']!['extent']);
    final tuned = soft.withOverrides({'edge.blur': 9, 'frost': 3});
    expect(tuned['blur'], 9);
    expect(tuned.values.containsKey('frost'), isFalse);
  });

  test('the shipped table has every style in both appearances', () {
    for (final style in ScrollEdgeStyle.values) {
      for (final appearance in ['dark', 'light']) {
        expect(ios27ScrollEdgeTable.containsKey('$appearance.${style.name}'), isTrue);
      }
    }
  });

  test('missing fields fall back to defaults', () {
    const material = ScrollEdgeMaterial({});
    expect(material['knee'], ScrollEdgeMaterial.defaults['knee']);
  });
}
