import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

enum Tone { neutral, passive, success, warning, error }

Color toneColor(AppSkin skin, Tone tone) {
  switch (tone) {
    case Tone.success:
      return skin.green;
    case Tone.warning:
      return skin.amber;
    case Tone.error:
      return skin.red;
    case Tone.passive:
      return skin.textTertiary;
    case Tone.neutral:
      return skin.textSecondary;
  }
}
