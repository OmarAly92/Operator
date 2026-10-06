import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ConnectionRow extends StatelessWidget {
  const ConnectionRow({
    super.key,
    required this.name,
    required this.host,
    required this.address,
    required this.lastConnectedLabel,
    required this.connecting,
    required this.active,
    required this.onTap,
    this.onMenuTap,
    this.error,
    this.onScanAgain,
    this.activeDotKey,
  });

  final String name;
  final String host;
  final String address;
  final String lastConnectedLabel;
  final bool connecting;
  final bool active;
  final ConnectionErrorCopy? error;
  final VoidCallback? onScanAgain;
  final Key? activeDotKey;
  final VoidCallback onTap;
  final VoidCallback? onMenuTap;

  Color _brandInk(BuildContext context) {
    final skin = context.skin;
    return skin.themeMode == ThemeMode.dark ? skin.accent : const Color(0xFF0E6E37);
  }

  String _metaText() {
    if (connecting) return 'Connecting…';
    return '$address · ${isLocalNetworkHost(host) ? 'LAN' : 'Remote'} · $lastConnectedLabel';
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: connecting ? null : onTap,
      borderRadius: BorderRadius.zero,
      backgroundColor: connecting ? skin.bgElevated : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      constraints: const BoxConstraints(minHeight: 62),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: connecting ? skin.tintGreen : skin.bgElevated,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
            child: Center(
              child: connecting
                  ? _ConnectingIcon(color: _brandInk(context))
                  : Icon(Icons.computer, size: 18, color: skin.textSecondary),
            ),
          ),
          const HorizontalSpace(11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (active) ...[
                      Container(
                        key: activeDotKey,
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: skin.accent, shape: BoxShape.circle),
                      ),
                      const HorizontalSpace(6),
                    ],
                    Flexible(child: AppText(name, style: AppTextStyle.style14p5SemiBold)),
                  ],
                ),
                const VerticalSpace(3),
                AppText(_metaText(), style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
                if (error != null) ...[
                  const VerticalSpace(4),
                  AppText(
                    error!.message,
                    style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                    maxLines: 3,
                  ),
                  if (onScanAgain != null)
                    GestureDetector(
                      onTap: onScanAgain,
                      child: AppText(
                        'Scan again',
                        style: AppTextStyle.style11SemiBold.copyWith(color: skin.accentText),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (onMenuTap != null)
            AppContainer(
              onTap: onMenuTap,
              width: 30,
              height: 30,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Center(child: Icon(Icons.more_vert, size: 18, color: skin.textFaint)),
            ),
        ],
      ),
    );
  }
}

class _ConnectingIcon extends StatefulWidget {
  const _ConnectingIcon({required this.color});

  final Color color;

  @override
  State<_ConnectingIcon> createState() => _ConnectingIconState();
}

class _ConnectingIconState extends State<_ConnectingIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.spin)
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(Icons.autorenew, size: 18, color: widget.color),
    );
  }
}
