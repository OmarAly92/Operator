/// Liquid Glass Effect for Flutter
library;

import 'package:flutter/foundation.dart' show kDebugMode;

export 'src/accessibility/glass_accessibility.dart' show GlassAccessibility, GlassAccessibilityData;
export 'src/api/glass.dart' show Glass, GlassKind;
export 'src/api/glass_dimming.dart' show GlassDimming;
export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
export 'src/api/glass_effect_transition.dart' show GlassEffectTransition;
export 'src/api/glass_foreground.dart' show GlassForeground;
export 'src/api/glass_namespace.dart' show GlassEffectID, GlassEffectUnion, GlassNamespace;
export 'src/api/glass_shape.dart';
export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
export 'src/fake_glass.dart' show FakeGlass;
export 'src/glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'src/internal/glass_drag_builder.dart' show GestureMode;
export 'src/liquid_glass.dart' show LiquidGlass;
export 'src/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'src/liquid_glass_settings.dart' show LiquidGlassSettings;
export 'src/liquid_shape.dart';
export 'src/logging.dart' show LgrLogs;
export 'src/material/glass_material.dart' show GlassMaterial;
export 'src/material/glass_material_override.dart' show GlassMaterialOverride;
export 'src/material/ios27.dart' show ios27Table;
export 'src/material/ios27_scroll_edge.dart' show ios27ScrollEdgeTable;
export 'src/material/scroll_edge_material.dart' show ScrollEdgeMaterial, ScrollEdgeStyle;
export 'src/motion/glass_animation.dart' show GlassAnimation, GlassAnimationScope, debugResetGlassAnimation, withGlassAnimation;
export 'src/rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'src/scroll_edge/scroll_edge_effect.dart' show ScrollEdge, ScrollEdgeEffect;
export 'src/scroll_edge/scroll_under_bars.dart' show ScrollUnderBars;
export 'src/stretch.dart'
    show LiquidStretch, OffsetResistanceExtension, RawLiquidStretch;

/// Whether to paint the liquid glass geometry texture for debugging purposes.
///
/// When enabled, geometry textures will be drawn directly instead of the
/// liquid glass effect.
///
/// Will be set to `false` in release builds.
@pragma('vm:platform-const-if', !kDebugMode)
bool debugPaintLiquidGlassGeometry = false;
