import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPermissionGate extends StatelessWidget {
  const CameraPermissionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, color: skin.textSecondary, size: 40),
            const VerticalSpace(14),
            AppText(
              'Operator needs your camera to scan the pairing QR code.',
              style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
            const VerticalSpace(20),
            PrimaryButton(text: 'Open Settings', onPressed: openAppSettings),
          ],
        ),
      ),
    );
  }
}
