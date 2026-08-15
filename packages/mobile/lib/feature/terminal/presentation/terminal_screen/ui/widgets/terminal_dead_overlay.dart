import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalDeadOverlay extends StatelessWidget {
  const TerminalDeadOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;

    return ColoredBox(
      color: context.skin.bgBase,
      child: AppEmptyState(
        icon: Icons.power_settings_new,
        title: shellOnly ? 'Shell closed' : 'Session terminated',
        message: shellOnly
            ? 'This worktree shell is no longer running.'
            : 'This session has no live terminal. Restore it to bring the agent back.',
        action: shellOnly
            ? null
            : PrimaryButton(
                text: cubit.restoring ? 'Restoring...' : 'Restore session',
                onPressed: cubit.restoring ? null : cubit.restore,
              ),
      ),
    );
  }
}
