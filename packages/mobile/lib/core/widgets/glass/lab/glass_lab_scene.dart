enum GlassLabScene {
  rest,
  sheet,
  corners;

  static GlassLabScene parse(String? raw) => switch (raw) {
        'sheet' => GlassLabScene.sheet,
        'corners' => GlassLabScene.corners,
        _ => GlassLabScene.rest,
      };

  static GlassLabScene? fromEnvironment() {
    const raw = String.fromEnvironment('GLASS_LAB_SCENE');
    return raw.isEmpty ? null : parse(raw);
  }
}
