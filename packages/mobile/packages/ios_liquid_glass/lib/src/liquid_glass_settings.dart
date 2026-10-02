import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';

/// Represents the settings for a liquid glass effect.
class LiquidGlassSettings with Equatable {
  /// Creates a new [LiquidGlassSettings] with the given settings.
  const LiquidGlassSettings({
    this.visibility = 1.0,
    this.glassColor = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20,
    this.blur = 5,
    this.chromaticAberration = .01,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = .5,
    this.ambientStrength = 0,
    this.refractiveIndex = 1.2,
    this.saturation = 1.5,
    this.fillRatio = 0.8,
    this.toneBlack = 0,
    this.toneMid = 0.5,
    this.toneWhite = 1,
    this.tintBlack = 1,
    this.tintWhite = 1,
    this.outline = 0,
    this.outlineTop = 0,
    this.outlineWidth = 0.5,
    this.specular = 0,
    this.specularWidth = 1.5,
    this.specularPower = 2,
    this.specularFill = 0.4,
    this.sheen = 0,
    this.sheenWidth = 3,
  });

  /// Creates a new [LiquidGlassSettings] with the given settings where each
  /// setting works like it does in Figma, where it is a percentage from
  /// 0 to 100.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
    double visibility = 1.0,
    double lightIntensity = 50,
    double lightAngle = 0.5 * pi,
    Color glassColor = const Color.fromARGB(0, 255, 255, 255),
  }) : this(
          visibility: visibility,
          refractiveIndex: 1 + (refraction / 100) * 0.2,
          thickness: depth,
          chromaticAberration: 4 * (dispersion / 100),
          lightIntensity: lightIntensity / 100,
          blur: frost,
          lightAngle: lightAngle,
          ambientStrength: 0.1,
          saturation: 1.5,
          glassColor: glassColor,
        );

  /// Retrieves the nearest [LiquidGlassSettings] from the widget tree.
  ///
  /// This will look for the nearest ancestor [LiquidGlassLayer] or
  /// [LiquidGlassRenderScope] widget in the widget tree.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// A factor that can be used to scale all thickness-related properties.
  ///
  /// Defaults to 1.0.
  final double visibility;

  /// The color tint of the glass effect.
  ///
  /// Opacity defines the intensity of the tint.
  final Color glassColor;

  /// The effective glass color taking visibility into account.
  Color get effectiveGlassColor =>
      glassColor.withValues(alpha: glassColor.a * visibility);

  /// The thickness of the glass surface.
  ///
  /// Thicker surfaces refract the light more intensely.
  final double thickness;

  /// The effective thickness taking visibility into account.
  double get effectiveThickness => thickness * visibility;

  /// The blur of the glass effect.
  ///
  /// Higher values create a more frosted appearance.
  ///
  /// Defaults to 0.
  final double blur;

  /// The effective blur taking visibility into account.
  double get effectiveBlur => blur * visibility;

  /// The chromatic aberration of the glass effect (WIP).
  ///
  /// This is a little ugly still.
  ///
  /// Higher values create more pronounced color fringes.
  final double chromaticAberration;

  /// The effective chromatic aberration taking visibility into account.
  double get effectiveChromaticAberration => chromaticAberration * visibility;

  /// The angle of the light source in radians.
  ///
  /// This determines where the highlights on shapes will come from.
  final double lightAngle;

  /// The intensity of the light source.
  ///
  /// Higher values create more pronounced highlights.
  final double lightIntensity;

  /// The effective light intensity taking visibility into account.
  double get effectiveLightIntensity => lightIntensity * visibility;

  /// The strength of the ambient light.
  ///
  /// Higher values create more pronounced ambient light.
  final double ambientStrength;

  /// The effective ambient strength taking visibility into account.
  double get effectiveAmbientStrength => ambientStrength * visibility;

  /// The strength of the refraction.
  ///
  /// Higher values create more pronounced refraction.
  /// Defaults to 1.51
  final double refractiveIndex;

  /// The saturation adjustment for pixels that shine through the glass.
  ///
  /// 1.0 means no change, values < 1.0 desaturate the background,
  /// values > 1.0 increase saturation.
  /// Defaults to 1.0
  final double saturation;

  /// The effective saturation taking visibility into account.
  double get effectiveSaturation => 1 + (saturation - 1) * visibility;

  final double fillRatio;

  final double toneBlack;

  double get effectiveToneBlack => toneBlack * visibility;

  final double toneMid;

  double get effectiveToneMid => 0.5 + (toneMid - 0.5) * visibility;

  final double toneWhite;

  double get effectiveToneWhite => 1 + (toneWhite - 1) * visibility;

  final double tintBlack;

  final double tintWhite;

  final double outline;

  double get effectiveOutline => outline * visibility;

  final double outlineTop;

  double get effectiveOutlineTop => outlineTop * visibility;

  final double outlineWidth;

  final double specular;

  double get effectiveSpecular => specular * visibility;

  final double specularWidth;

  final double specularPower;

  final double specularFill;

  final double sheen;

  double get effectiveSheen => sheen * visibility;

  final double sheenWidth;

  /// Creates a new [LiquidGlassSettings] with the given settings.
  LiquidGlassSettings copyWith({
    double? visibility,
    Color? glassColor,
    double? thickness,
    double? blur,
    double? chromaticAberration,
    double? blend,
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    double? refractiveIndex,
    double? saturation,
    double? fillRatio,
    double? toneBlack,
    double? toneMid,
    double? toneWhite,
    double? tintBlack,
    double? tintWhite,
    double? outline,
    double? outlineTop,
    double? outlineWidth,
    double? specular,
    double? specularWidth,
    double? specularPower,
    double? specularFill,
    double? sheen,
    double? sheenWidth,
  }) =>
      LiquidGlassSettings(
        visibility: visibility ?? this.visibility,
        glassColor: glassColor ?? this.glassColor,
        thickness: thickness ?? this.thickness,
        blur: blur ?? this.blur,
        chromaticAberration: chromaticAberration ?? this.chromaticAberration,
        lightAngle: lightAngle ?? this.lightAngle,
        lightIntensity: lightIntensity ?? this.lightIntensity,
        ambientStrength: ambientStrength ?? this.ambientStrength,
        refractiveIndex: refractiveIndex ?? this.refractiveIndex,
        saturation: saturation ?? this.saturation,
        fillRatio: fillRatio ?? this.fillRatio,
        toneBlack: toneBlack ?? this.toneBlack,
        toneMid: toneMid ?? this.toneMid,
        toneWhite: toneWhite ?? this.toneWhite,
        tintBlack: tintBlack ?? this.tintBlack,
        tintWhite: tintWhite ?? this.tintWhite,
        outline: outline ?? this.outline,
        outlineTop: outlineTop ?? this.outlineTop,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        specular: specular ?? this.specular,
        specularWidth: specularWidth ?? this.specularWidth,
        specularPower: specularPower ?? this.specularPower,
        specularFill: specularFill ?? this.specularFill,
        sheen: sheen ?? this.sheen,
        sheenWidth: sheenWidth ?? this.sheenWidth,
      );

  @override
  List<Object?> get props => [
        visibility,
        glassColor,
        thickness,
        blur,
        chromaticAberration,
        lightAngle,
        lightIntensity,
        ambientStrength,
        refractiveIndex,
        saturation,
        fillRatio,
        toneBlack,
        toneMid,
        toneWhite,
        tintBlack,
        tintWhite,
        outline,
        outlineTop,
        outlineWidth,
        specular,
        specularWidth,
        specularPower,
        specularFill,
        sheen,
        sheenWidth,
      ];
}
