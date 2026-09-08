import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

/// A filter chip, matching the prototype's `agentChip`/`pillStyle` spec
/// (`docs/design/components.md`): pill radius, tinted-green active state.
///
/// The prototype's `agentChip` (sessions board filter row) and `pillStyle`
/// (pull requests filter row) are two distinct specs that happen to share
/// the active/tint/brand-ink logic but differ when inactive: `agentChip` is
/// a bordered `bgSurface` chip at 12.5px, `pillStyle` is a borderless
/// `bgElevated` chip at 12px with `textTertiary` (not `textSecondary`) text.
/// [dense] switches to the `pillStyle` variant.
class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.label, required this.active, this.onTap, this.count, this.dense = false});

  final String label;
  final bool active;
  final void Function()? onTap;
  final bool dense;

  /// Optional trailing count badge, e.g. the sessions-board filter row's
  /// per-chip session count (`docs/design/sessions_board/sessions_board.md`).
  final int? count;

  void Function()? get _onTap {
    final handler = onTap;
    if (handler == null) return null;
    return () {
      Haptics.select();
      handler();
    };
  }

  /// The prototype hardcodes a darker green (`#117E3F`) for active chip text
  /// in light mode instead of reusing `skin.accent` directly (`accent` is
  /// too bright/low-contrast as text-on-tint there); dark mode uses
  /// `skin.accent` as-is since it already reads well on `tintGreen`. Not
  /// promoted to a shared `AppSkin` getter — this is the only call site.
  Color _activeTextColor(BuildContext context) {
    final skin = context.skin;
    return skin.themeMode == ThemeMode.dark ? skin.accent : const Color(0xFF117E3F);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final textColor = active ? _activeTextColor(context) : (dense ? skin.textTertiary : skin.textSecondary);
    return AppContainer(
      onTap: _onTap,
      hapticsOnTap: false,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 6 : 7),
      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
      backgroundColor: active ? skin.tintGreen : (dense ? skin.bgElevated : skin.bgSurface),
      border: dense ? null : Border.all(color: active ? Colors.transparent : skin.borderDefault),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(
            label,
            style: (dense ? AppTextStyle.style12SemiBold : AppTextStyle.style12p5SemiBold).copyWith(color: textColor),
          ),
          if (count != null) ...[
            const HorizontalSpace(5),
            AppText(
              '$count',
              style: AppTextStyle.mono11Regular.copyWith(
                color: active ? textColor : skin.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
