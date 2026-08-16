import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, this.footer, required this.children});

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Container(height: 1, color: skin.borderSubtle));
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: AppText(
              title!.toUpperCase(),
              style: AppTextStyle.style11Bold.copyWith(color: skin.textTertiary, letterSpacing: 1.2),
            ),
          ),
        ],
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: skin.bgSurface, borderRadius: BorderRadius.circular(12)),
          child: Column(children: rows),
        ),
        if (footer != null) ...[
          const VerticalSpace(6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: AppText(
              footer!,
              style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary),
              maxLines: 3,
            ),
          ),
        ],
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.leading,
    this.onTap,
    this.destructive = false,
    this.loading = false,
    this.disabled = false,
    this.trailing,
  });

  final IconData? icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? leading;
  final void Function()? onTap;
  final bool destructive;
  final bool loading;
  final bool disabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final labelColor = destructive ? skin.red : skin.textPrimary;
    final iconColor = destructive ? skin.red : skin.textSecondary;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: iconColor),
              const HorizontalSpace(10),
            ],
            Expanded(
              child: AppText(label, style: AppTextStyle.style15Regular.copyWith(color: labelColor)),
            ),
            if (trailing != null)
              trailing!
            else ...[
              if (loading) ...[const AppLoader(strokeWidth: 2), const HorizontalSpace(8)],
              if (leading != null) ...[leading!, const HorizontalSpace(8)],
              if (value != null)
                AppText(
                  value!,
                  style: AppTextStyle.style13Regular.copyWith(color: valueColor ?? skin.textTertiary),
                ),
              if (onTap != null) ...[
                const HorizontalSpace(4),
                Icon(Icons.chevron_right, size: 18, color: skin.textFaint),
              ],
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return AppInkWell(onTap: (disabled || loading) ? null : onTap, child: content);
  }
}

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: skin.textSecondary),
            const HorizontalSpace(10),
            Expanded(
              child: AppText(
                label,
                style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
              ),
            ),
            if (busy) ...[const AppLoader(strokeWidth: 2), const HorizontalSpace(10)],
            Switch(
              value: value,
              activeThumbColor: skin.onAccent,
              activeTrackColor: skin.blue,
              onChanged: disabled || busy ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
