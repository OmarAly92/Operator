import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

/// A danger banner that sits above the still-visible block/terminal content
/// when the agent controller has stopped — it never replaces the body.
class TerminalDeadOverlay extends StatelessWidget {
  const TerminalDeadOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.tintRed,
        border: Border(bottom: BorderSide(color: skin.borderDefault)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.power_settings_new, size: 16, color: skin.red),
              const HorizontalSpace(8),
              Expanded(
                child: AppText(
                  shellOnly ? 'Shell closed' : 'Session terminated',
                  style: AppTextStyle.style12SemiBold.copyWith(color: skin.red),
                ),
              ),
            ],
          ),
          const VerticalSpace(4),
          AppText(
            shellOnly
                ? 'This worktree shell is no longer running.'
                : 'This session has no live terminal. Restore it to bring the agent back.',
            style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
          ),
          if (!shellOnly) ...[
            const VerticalSpace(10),
            PrimaryButton.expand(
              text: cubit.restoring ? 'Restoring...' : 'Restore session',
              onPressed: cubit.restoring ? null : cubit.restore,
              fixedSize: const Size.fromHeight(36),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ],
        ],
      ),
    );
  }
}
