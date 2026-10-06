import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';

void main() {
  test('reads scene, backdrop and bare mode', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'menu.bar', 'backdrop': 'photo', 'bare': true});
    expect(launch?.scene, 'menu.bar');
    expect(launch?.backdrop, 'photo');
    expect(launch?.bare, isTrue);
  });

  test('defaults the backdrop and bare mode', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'tabbar.rest', 'backdrop': ''});
    expect(launch?.backdrop, GlassLabLaunch.defaultBackdrop);
    expect(launch?.bare, isFalse);
  });

  test('returns null without a scene', () {
    expect(GlassLabLaunch.fromJson(const <String, dynamic>{}), isNull);
    expect(GlassLabLaunch.fromJson({'scene': ''}), isNull);
    expect(GlassLabLaunch.fromJson('tabbar.rest'), isNull);
  });

  test('consume reads the launch file once and deletes it', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('{"scene": "toggle", "backdrop": "white"}');
    expect(GlassLabLaunch.consume(directory)?.scene, 'toggle');
    expect(File('${directory.path}/${GlassLabLaunch.launchFile}').existsSync(), isFalse);
    expect(GlassLabLaunch.consume(directory), isNull);
  });

  test('consume ignores and deletes a malformed file', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('not json');
    expect(GlassLabLaunch.consume(directory), isNull);
    expect(File('${directory.path}/${GlassLabLaunch.launchFile}').existsSync(), isFalse);
  });
}
