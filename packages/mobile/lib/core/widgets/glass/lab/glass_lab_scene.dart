enum GlassLabScene {
  rest,
  sheet,
  corners,
  lifted,
  sheetscroll;

  static GlassLabScene parse(String? raw) => switch (raw) {
        'sheet' => GlassLabScene.sheet,
        'corners' => GlassLabScene.corners,
        'lifted' => GlassLabScene.lifted,
        'sheetscroll' => GlassLabScene.sheetscroll,
        _ => GlassLabScene.rest,
      };

  static GlassLabScene? fromEnvironment() {
    const raw = String.fromEnvironment('GLASS_LAB_SCENE');
    return raw.isEmpty ? null : parse(raw);
  }
}
