import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
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
      appBar: const GlobalAppbar.main(titleText: 'Settings'),
      body: SettingsBody(onOpenBoard: onOpenBoard),
    ),
  );
}
