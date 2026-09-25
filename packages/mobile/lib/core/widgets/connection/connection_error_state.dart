import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/fade_up_entrance.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionErrorState extends StatelessWidget {
  const ConnectionErrorState({
    super.key,
    required this.reason,
    required this.host,
    required this.port,
    required this.onRetry,
    required this.onSwitchDesktop,
    this.desktopName,
    this.onRePair,
  });

  static const Key retryKey = ValueKey('connection-error-retry');
  static const Key switchKey = ValueKey('connection-error-switch');

  final ConnectionFailure reason;
  final String host;
  final String port;
  final String? desktopName;
  final VoidCallback onRetry;
  final VoidCallback onSwitchDesktop;
  final VoidCallback? onRePair;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final copy = describeConnectionFailure(
      reason,
      host: host,
      port: port,
      platform: Theme.of(context).platform,
      desktopName: desktopName,
    );
    final rePair = copy.isAuth ? onRePair : null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        child: FadeUpEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: skin.bgElevated, shape: BoxShape.circle),
                child: Icon(
                  copy.isAuth ? Icons.lock_outline_rounded : Icons.wifi_off_rounded,
                  size: 32,
                  color: copy.isAuth ? skin.red : skin.textSecondary,
                ),
              ),
              const VerticalSpace(20),
              AppText(
                copy.title,
                style: AppTextStyle.style21Bold.copyWith(letterSpacing: -0.3),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              const VerticalSpace(8),
              AppText(
                copy.message,
                style: AppTextStyle.style13p5Regular.copyWith(color: skin.textSecondary, height: 1.45),
                textAlign: TextAlign.center,
                maxLines: 4,
              ),
              if (copy.showLocalNetworkHint) ...[
                const VerticalSpace(10),
                AppText(
                  kLocalNetworkHint,
                  style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                ),
              ],
              const VerticalSpace(24),
              PrimaryButton(
                key: retryKey,
                text: rePair == null ? 'Retry' : 'Re-pair',
                onPressed: rePair ?? onRetry,
              ),
              const VerticalSpace(6),
              TextButton(
                key: switchKey,
                onPressed: onSwitchDesktop,
                child: AppText(
                  'Switch desktop',
                  style: AppTextStyle.style13p5Medium.copyWith(color: skin.accentText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
