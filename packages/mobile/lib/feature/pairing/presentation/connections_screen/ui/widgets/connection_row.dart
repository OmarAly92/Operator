import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

/// A single row in the "Your desktops" group card
/// (`docs/design/connections/connections.md`). Takes primitive fields
/// rather than the whole `SavedConnection` model so it stays reusable.
class ConnectionRow extends StatelessWidget {
  const ConnectionRow({
    super.key,
    required this.name,
    required this.address,
    required this.lastConnectedLabel,
    required this.connecting,
    required this.onTap,
    required this.onMenuTap,
  });

  final String name;
  final String address;
  final String? lastConnectedLabel;
  final bool connecting;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;

  /// The prototype's `brandInk` value on the connecting icon wrap — same
  /// brand-on-tint concept as `AppPill`'s active-chip text judgment call
  /// (`docs/design/components.md`), reused here rather than adding a third
  /// variant.
  Color _brandInk(BuildContext context) {
    final skin = context.skin;
    return skin.themeMode == ThemeMode.dark ? skin.accent : const Color(0xFF117E3F);
  }

  String _metaText() {
    if (connecting) return 'Connecting…';
    if (lastConnectedLabel != null) return '$address · last connected $lastConnectedLabel';
    return '$address · not connected yet';
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
                AppText(name, style: AppTextStyle.style14p5SemiBold),
                const VerticalSpace(3),
                AppText(_metaText(), style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary)),
              ],
            ),
          ),
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

/// The connecting-row's spinning `progress_activity` glyph
/// (`AppMotion.spin`, 1000ms linear infinite). Mounted only while a row is
/// connecting — a bounded ~900ms window, not one of the perpetual
/// animations `components.md`'s testing note warns about.
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
