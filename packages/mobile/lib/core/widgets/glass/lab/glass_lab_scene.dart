enum GlassLabScene {
  rest,
  sheet,
  corners,
  lifted;

  static GlassLabScene parse(String? raw) => switch (raw) {
        'sheet' => GlassLabScene.sheet,
        'corners' => GlassLabScene.corners,
        'lifted' => GlassLabScene.lifted,
        _ => GlassLabScene.rest,
      };

  static GlassLabScene? fromEnvironment() {
    const raw = String.fromEnvironment('GLASS_LAB_SCENE');
    return raw.isEmpty ? null : parse(raw);
  }
}
