import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';

class TerminalBody extends StatelessWidget {
  const TerminalBody({super.key});

  Future<void> _confirmKill(BuildContext context) async {
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;
    final confirmed = await AppDialog.confirm(
      context,
      title: shellOnly ? 'Close shell?' : 'Kill session?',
      message: shellOnly
          ? 'This stops the worktree shell.'
          : 'This stops ${cubit.args.sessionId}.',
      confirmLabel: shellOnly ? 'Close' : 'Kill',
      destructive: true,
    );
    if (confirmed) await cubit.terminate();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: BlocBuilder<TerminalCubit, TerminalState>(
        buildWhen: (previous, current) => current is TerminalReadyState,
        builder: (context, state) {
          final cubit = context.read<TerminalCubit>();
          final banner = cubit.banner;

          return Column(
            children: [
              TerminalStatusBar(
                onKill: () => _confirmKill(context),
                onRestore: cubit.restore,
              ),
              if (banner != null)
                InkWell(
                  onTap: cubit.dismissBanner,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border(bottom: BorderSide(color: skin.borderDefault)),
                    ),
                    child: AppText(
                      '$banner (tap to dismiss)',
                      style: AppTextStyle.style12Regular.copyWith(color: skin.attention),
                      maxLines: 3,
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: TerminalSurface()),
                    if (cubit.notFound) const Positioned.fill(child: TerminalDeadOverlay()),
                    BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>(
                      buildWhen: (previous, current) => current is InterfaceSwitchReadyState,
                      builder: (context, _) =>
                          context.read<InterfaceSwitchCubit>().active
                          ? const Positioned.fill(child: InterfaceSwitchOverlay())
                          : const Positioned.fill(child: SizedBox.shrink()),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.only(bottom: dockInset(keyboard, safeBottom)),
                decoration: BoxDecoration(
                  color: skin.bgSurface,
                  border: Border(top: BorderSide(color: skin.borderSubtle)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [TerminalKeyRow(), TerminalComposer()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
