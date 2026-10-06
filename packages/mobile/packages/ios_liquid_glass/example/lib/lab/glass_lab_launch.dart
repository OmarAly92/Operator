import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class GlassLabLaunch {
  const GlassLabLaunch({
    required this.scene,
    this.backdrop = defaultBackdrop,
    this.bare = false,
    this.material = const {},
    this.materialSide,
    this.marker = false,
    this.visibility,
    this.blurRamp,
  });

  static const String defaultBackdrop = 'stripes';
  static const String launchFile = 'launch.json';
  static Directory directory = Directory('');

  final String scene;
  final String backdrop;
  final bool bare;
  final Map<String, double> material;
  final double? materialSide;
  final bool marker;
  final double? visibility;
  final double? blurRamp;

  static GlassLabLaunch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final scene = json['scene'];
    if (scene is! String || scene.isEmpty) return null;
    final backdrop = json['backdrop'];
    final material = json['material'];
    final materialSide = json['materialSide'];
    final visibility = json['visibility'];
    final blurRamp = json['blurRamp'];
    return GlassLabLaunch(
      scene: scene,
      backdrop: backdrop is String && backdrop.isNotEmpty ? backdrop : defaultBackdrop,
      bare: json['bare'] == true,
      material: material is Map<String, dynamic>
          ? {for (final entry in material.entries) if (entry.value is num) entry.key: (entry.value as num).toDouble()}
          : const {},
      materialSide: materialSide is num ? materialSide.toDouble() : null,
      marker: json['marker'] == true,
      visibility: visibility is num ? visibility.toDouble() : null,
      blurRamp: blurRamp is num ? blurRamp.toDouble() : null,
    );
  }

  static GlassLabLaunch? consume(Directory labDirectory) {
    final file = File('${labDirectory.path}/$launchFile');
    if (!file.existsSync()) return null;
    try {
      return fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException {
      return null;
    } finally {
      file.deleteSync();
    }
  }

  static Future<GlassLabLaunch?> load() async {
    directory = Directory('${(await getApplicationDocumentsDirectory()).path}/glass_lab');
    return consume(directory);
  }
}
