import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:flutter/services.dart';

class GlobalAppbar extends StatelessWidget implements PreferredSizeWidget {
  const GlobalAppbar.main({
    this.leading,
    this.title,
    this.titleText,
    this.actions,
    this.backgroundColor,
    this.centerTitle = false,
    this.elevation,
    this.leadingWidth,
    this.surfaceTintColor,
    this.bottom,
    this.hasBorder = false,
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
    this.backgroundColor,
    this.centerTitle = true,
    this.elevation,
    this.leadingWidth,
    this.surfaceTintColor,
    this.bottom,
    super.key,
    this.hasBorder = false,
    this.leadingText,
    this.onAppPopIconPressed,
    this.systemOverlayStyle,
  }) : _isSub = true;

  final bool _isSub;
  final Widget? leading;
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final double? elevation;
  final double? leadingWidth;
  final Color? surfaceTintColor;
  final bool? centerTitle;
  final bool hasBorder;
  final PreferredSizeWidget? bottom;
  final String? leadingText;
  final void Function()? onAppPopIconPressed;
  final SystemUiOverlayStyle? systemOverlayStyle;

  void Function()? get _onAppPopIconPressed {
    final handler = onAppPopIconPressed;
    if (handler == null) return null;
    return () {
      Haptics.tap();
      handler();
    };
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor ?? context.skin.bgSurface,
      centerTitle: centerTitle,
      leadingWidth: leadingWidth ?? 120,
      leading: _isSub
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading ?? BackButton(onPressed: _onAppPopIconPressed),
                if (leadingText != null)
                  Expanded(
                    child: AppText(
                      leadingText!,
                      style: AppTextStyle.style12Regular.copyWith(
                        color: context.skin.textSecondary,
                      ),
                    ),
                  ),
              ],
            )
          : leading,
      title: buildTitle(),
      actions: actions,
      surfaceTintColor: surfaceTintColor,
      elevation: elevation,
      bottom: bottom,
      systemOverlayStyle: systemOverlayStyle,
      shape: hasBorder
          ? Border(bottom: BorderSide(color: context.skin.borderSubtle))
          : const Border(bottom: BorderSide(color: Colors.transparent)),
    );
  }

  Widget? buildTitle() {
    if (title != null) {
      return title!;
    }

    if (titleText != null) {
      return AppText(
        titleText!,
        style: _isSub
            ? AppTextStyle.style16SemiBold
            : AppTextStyle.style19SemiBold,
      );
    }

    return null;
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));
}
