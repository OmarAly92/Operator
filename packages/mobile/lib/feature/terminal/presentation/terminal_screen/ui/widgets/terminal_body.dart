import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/keyboard_inset.dart';
import 'package:operator_mobile/core/widgets/chat/chat_insets.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/glass/frosted_header.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/subagent_strip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';

class TerminalBody extends StatefulWidget {
  const TerminalBody({super.key});

  @override
  State<TerminalBody> createState() => _TerminalBodyState();
}

class _TerminalBodyState extends State<TerminalBody> {
  static const double kDockSide = 8;

  final GlobalKey<BlocksBodyState> _blocks = GlobalKey<BlocksBodyState>();
  final ValueNotifier<double> _dockHeight = ValueNotifier<double>(TerminalComposer.restHeight);
  final ValueNotifier<double> _frost = ValueNotifier<double>(0);
  final ValueNotifier<double> _clear = ValueNotifier<double>(0);
  double _topExtra = 0;

  @override
  void dispose() {
    _dockHeight.dispose();
    _frost.dispose();
    _clear.dispose();
    super.dispose();
  }

  bool _onScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _frost.value = FrostedBand.visibilityFor(metrics.pixels - metrics.minScrollExtent);
    }
    return false;
  }

  void _onTopExtra(double height) {
    if (!mounted || height == _topExtra) return;
    setState(() => _topExtra = height);
  }

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
    final gap = math.max(dockInset(keyboard, safeBottom), kMinDockInset);

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

                final top = TerminalChatHeader.heightOf(context) + _topExtra;

                return ChatInsets(
                  bottom: _dockHeight,
                  gap: gap,
                  top: top,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: blocksMode
                            ? NotificationListener<Notification>(
                                onNotification: _onScroll,
                                child: BlocksBody(key: _blocks, onRerun: _fillComposer),
                              )
                            : ValueListenableBuilder<double>(
                                valueListenable: _dockHeight,
                                builder: (context, height, child) => Padding(
                                  padding: EdgeInsets.only(top: top, bottom: height + gap),
                                  child: child,
                                ),
                                child: const RawTerminalPane(),
                              ),
                      ),
                      Positioned(
                        left: kDockSide,
                        right: kDockSide,
                        bottom: gap,
                        child: MeasuredHeight(
                          onHeight: (height) => _dockHeight.value = height,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (blocksMode && !cubit.args.shellOnly) SubagentStrip(parentTitle: cubit.args.title),
                              if (!blocksMode) const TerminalKeyRow(),
                              const TerminalComposer(),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TerminalChatHeader(
                              onFind: () => _blocks.currentState?.openFind(),
                              onKill: () => _confirmKill(context),
                              frost: blocksMode ? _frost : _clear,
                            ),
                            MeasuredHeight(
                              onHeight: _onTopExtra,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
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
                                  if (cubit.notFound) const TerminalDeadOverlay(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}
