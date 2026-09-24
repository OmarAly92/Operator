import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_bar_item.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlobalAppbar extends StatelessWidget implements PreferredSizeWidget {
  const GlobalAppbar.main({
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.centerTitle = false,
    this.bottom,
    super.key,
    this.leadingText,
    this.onAppPopIconPressed,
    this.systemOverlayStyle,
  }) : _isSub = false;

  const GlobalAppbar.sub({
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.centerTitle = true,
    this.bottom,
    super.key,
    this.leadingText,
    this.onAppPopIconPressed,
    this.systemOverlayStyle,
  }) : _isSub = true;

  static const double _maxTextScaleFactor = 1.8;

  final bool _isSub;
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final bool? centerTitle;
  final PreferredSizeWidget? bottom;
  final String? leadingText;
  final void Function()? onAppPopIconPressed;
  final SystemUiOverlayStyle? systemOverlayStyle;

  Widget? _buildLeading(BuildContext context) {
    if (!_isSub) return leading == null ? null : GlassBarItem(child: leading!);
    final button = leading != null
        ? GlassBarItem(child: leading!)
        : GlassButton.icon(
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: 'Back',
            foreground: context.skin.textPrimary,
            onPressed: onAppPopIconPressed ?? () => Navigator.maybePop(context),
          );
    if (leadingText == null) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(width: 6),
        Flexible(
          child: AppText(
            leadingText!,
            style: AppTextStyle.style12Regular.copyWith(color: context.skin.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget? _buildMiddle() {
    final middle = buildTitle();
    if (middle == null) return null;
    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      fit: OverflowBoxFit.deferToChild,
      child: middle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final trailing = actions ?? const <Widget>[];
    final leadingWidget = _buildLeading(context);
    final overlay = systemOverlayStyle ??
        (skin.themeMode == ThemeMode.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Padding(
        padding: EdgeInsets.only(top: media.padding.top + GlassMetrics.toolbarTopGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: GlassMetrics.toolbarSideInset),
              child: SizedBox(
                height: GlassMetrics.hitTarget,
                child: GlassScope(
                  variant: GlassVariant.regular,
                  size: GlassMetrics.hitTarget,
                  child: MediaQuery(
                    data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScaleFactor)),
                    child: NavigationToolbar(
                      leading: leadingWidget,
                      middle: _buildMiddle(),
                      trailing: trailing.isEmpty
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < trailing.length; i++) ...[
                                  if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                                  GlassBarItem(child: trailing[i]),
                                ],
                              ],
                            ),
                      centerMiddle: centerTitle ?? _isSub,
                      middleSpacing: leadingWidget == null ? 0 : GlassMetrics.toolbarItemGap,
                    ),
                  ),
                ),
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }

  Widget? buildTitle() {
    if (title != null) {
      return title!;
    }

    if (titleText != null) {
      return AppText(
        titleText!,
        style: _isSub ? AppTextStyle.style16SemiBold : AppTextStyle.style19SemiBold,
      );
    }

    return null;
  }

  @override
  Size get preferredSize => Size.fromHeight(
        GlassMetrics.hitTarget + GlassMetrics.toolbarTopGap + (bottom?.preferredSize.height ?? 0),
      );
}
