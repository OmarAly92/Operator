import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';

void main() {
  testWidgets('exposes the dense sizes the app actually uses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => const SizedBox.shrink(),
        ),
      ),
    );

    expect(AppTextStyle.style11Regular.fontWeight, FontWeight.w400);
    expect(AppTextStyle.style11Bold.fontWeight, FontWeight.w700);
    expect(AppTextStyle.style12SemiBold.fontWeight, FontWeight.w600);
    expect(AppTextStyle.style13Medium.fontWeight, FontWeight.w500);
  });

  testWidgets('mono styles fall back to platform monospace', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => const SizedBox.shrink(),
        ),
      ),
    );

    expect(AppTextStyle.mono11Bold.fontFamilyFallback, contains('monospace'));
    expect(AppTextStyle.mono11Bold.fontFamily, isNull);
  });
}
