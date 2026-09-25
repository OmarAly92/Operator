import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Set<String?> _values(String yaml, String key) =>
    RegExp('^\\s*$key: "(#[0-9A-Fa-f]{6})"', multiLine: true).allMatches(yaml).map((m) => m.group(1)?.toUpperCase()).toSet();

void main() {
  test('the native splash hands off to the skin background with no colour jump', () {
    final yaml = File('flutter_native_splash.yaml').readAsStringSync();

    expect(_values(yaml, 'color'), {_hex(const LightSkin().bgBase)});
    expect(_values(yaml, 'color_dark'), {_hex(const DarkSkin().bgBase)});
  });
}
