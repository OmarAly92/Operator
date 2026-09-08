import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/widgets/settings_body.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onOpenBoard});

  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<SettingsCubit>(),
    child: Scaffold(
      backgroundColor: context.skin.bgBase,
      appBar: GlobalAppbar.main(
        backgroundColor: context.skin.bgChrome,
        hasBorder: true,
        title: AppText(
          'Settings',
          style: AppTextStyle.style19SemiBold.copyWith(
            fontFamily: 'Anthropic Sans Display',
            fontFamilyFallback: const ['Anthropic Sans Text'],
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SettingsBody(onOpenBoard: onOpenBoard),
    ),
  );
}
