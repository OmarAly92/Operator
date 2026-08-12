import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:operator_mobile/core/app_themes/text_style/font_weight_helper.dart';

sealed class AppTextStyle {
  static TextStyle _textStyle(double size, FontWeight weight) {
    return TextStyle(fontSize: size.spMin, fontWeight: weight);
  }

  static TextStyle _monoStyle(double size, FontWeight weight) {
    return TextStyle(
      fontSize: size.spMin,
      fontWeight: weight,
      fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
    );
  }

  static TextStyle get style9Regular => _textStyle(9, FontWeightHelper.regular);
  static TextStyle get style9Medium => _textStyle(9, FontWeightHelper.medium);
  static TextStyle get style9SemiBold => _textStyle(9, FontWeightHelper.semiBold);
  static TextStyle get style9Bold => _textStyle(9, FontWeightHelper.bold);

  static TextStyle get style10Regular => _textStyle(10, FontWeightHelper.regular);
  static TextStyle get style10Medium => _textStyle(10, FontWeightHelper.medium);
  static TextStyle get style10SemiBold => _textStyle(10, FontWeightHelper.semiBold);
  static TextStyle get style10Bold => _textStyle(10, FontWeightHelper.bold);

  static TextStyle get style11Regular => _textStyle(11, FontWeightHelper.regular);
  static TextStyle get style11Medium => _textStyle(11, FontWeightHelper.medium);
  static TextStyle get style11SemiBold => _textStyle(11, FontWeightHelper.semiBold);
  static TextStyle get style11Bold => _textStyle(11, FontWeightHelper.bold);

  static TextStyle get style12Regular => _textStyle(12, FontWeightHelper.regular);
  static TextStyle get style12Medium => _textStyle(12, FontWeightHelper.medium);
  static TextStyle get style12SemiBold => _textStyle(12, FontWeightHelper.semiBold);
  static TextStyle get style12Bold => _textStyle(12, FontWeightHelper.bold);

  static TextStyle get style13Regular => _textStyle(13, FontWeightHelper.regular);
  static TextStyle get style13Medium => _textStyle(13, FontWeightHelper.medium);
  static TextStyle get style13SemiBold => _textStyle(13, FontWeightHelper.semiBold);
  static TextStyle get style13Bold => _textStyle(13, FontWeightHelper.bold);

  static TextStyle get style14Regular => _textStyle(14, FontWeightHelper.regular);
  static TextStyle get style14Medium => _textStyle(14, FontWeightHelper.medium);
  static TextStyle get style14SemiBold => _textStyle(14, FontWeightHelper.semiBold);
  static TextStyle get style14Bold => _textStyle(14, FontWeightHelper.bold);

  static TextStyle get style15Regular => _textStyle(15, FontWeightHelper.regular);
  static TextStyle get style15Medium => _textStyle(15, FontWeightHelper.medium);
  static TextStyle get style15SemiBold => _textStyle(15, FontWeightHelper.semiBold);
  static TextStyle get style15Bold => _textStyle(15, FontWeightHelper.bold);

  static TextStyle get style16Regular => _textStyle(16, FontWeightHelper.regular);
  static TextStyle get style16Medium => _textStyle(16, FontWeightHelper.medium);
  static TextStyle get style16SemiBold => _textStyle(16, FontWeightHelper.semiBold);
  static TextStyle get style16Bold => _textStyle(16, FontWeightHelper.bold);

  static TextStyle get style17Regular => _textStyle(17, FontWeightHelper.regular);
  static TextStyle get style17Medium => _textStyle(17, FontWeightHelper.medium);
  static TextStyle get style17SemiBold => _textStyle(17, FontWeightHelper.semiBold);
  static TextStyle get style17Bold => _textStyle(17, FontWeightHelper.bold);

  static TextStyle get style19SemiBold => _textStyle(19, FontWeightHelper.semiBold);
  static TextStyle get style24Bold => _textStyle(24, FontWeightHelper.bold);
  static TextStyle get style26Bold => _textStyle(26, FontWeightHelper.bold);
  static TextStyle get style32Bold => _textStyle(32, FontWeightHelper.bold);

  static TextStyle get mono10Regular => _monoStyle(10, FontWeightHelper.regular);
  static TextStyle get mono10Bold => _monoStyle(10, FontWeightHelper.bold);

  static TextStyle get mono11Regular => _monoStyle(11, FontWeightHelper.regular);
  static TextStyle get mono11Bold => _monoStyle(11, FontWeightHelper.bold);

  static TextStyle get mono12Regular => _monoStyle(12, FontWeightHelper.regular);
  static TextStyle get mono12Bold => _monoStyle(12, FontWeightHelper.bold);

  static TextStyle get mono13Regular => _monoStyle(13, FontWeightHelper.regular);
  static TextStyle get mono13Bold => _monoStyle(13, FontWeightHelper.bold);
  static TextStyle get mono24Bold => _monoStyle(24, FontWeightHelper.bold);
}
