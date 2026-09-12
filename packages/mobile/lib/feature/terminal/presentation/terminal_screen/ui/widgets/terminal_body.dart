import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart';
import 'package:operator_mobile/core/utils/keyboard_inset.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';

class TerminalBody extends StatefulWidget {
  const TerminalBody({super.key});

  @override
  State<TerminalBody> createState() => _TerminalBodyState();
}

class _TerminalBodyState extends State<TerminalBody> {
  final GlobalKey<BlocksBodyState> _blocks = GlobalKey<BlocksBodyState>();

  Future<void> _confirmKill(BuildContext context) async {
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;
    Haptics.warning();
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

  void _fillComposer(String text) {
    final composer = context.read<TerminalCubit>().composer;
    composer.text = text;
    composer.selection = TextSelection.collapsed(offset: text.length);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: BlocBuilder<SessionViewCubit, SessionViewState>(
        buildWhen: (previous, current) => previous != current,
        builder: (context, viewState) =>
            BlocBuilder<TerminalCubit, TerminalState>(
              buildWhen: (previous, current) => current is TerminalReadyState,
              builder: (context, state) {
                final cubit = context.read<TerminalCubit>();
                final banner = cubit.banner;
                final blocksMode =
                    context.read<SessionViewCubit>().mode ==
                    SessionViewMode.blocks;

                return Column(
                  children: [
                    TerminalChatHeader(
                      onFind: () => _blocks.currentState?.openFind(),
                      onKill: () => _confirmKill(context),
                    ),
                    if (banner != null)
                      InkWell(
                        onTap: cubit.dismissBanner,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: skin.bgElevated,
                            border: Border(
                              bottom: BorderSide(color: skin.borderDefault),
                            ),
                          ),
                          child: AppText(
                            '$banner (tap to dismiss)',
                            style: AppTextStyle.style12Regular.copyWith(
                              color: skin.attention,
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ),
                    if (cubit.notFound) const TerminalDeadOverlay(),
                    Expanded(
                      child: blocksMode
                          ? BlocksBody(key: _blocks, onRerun: _fillComposer)
                          : const RawTerminalPane(),
                    ),
                    Container(
                      padding: EdgeInsets.only(
                        bottom: dockInset(keyboard, safeBottom),
                      ),
                      decoration: BoxDecoration(
                        color: skin.bgChrome,
                        border: Border(
                          top: BorderSide(color: skin.borderSubtle),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!blocksMode) const TerminalKeyRow(),
                          const TerminalComposer(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }
}
