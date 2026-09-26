import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/widgets/glass/frosted_header.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/utils/turn_elapsed.dart';
import 'package:operator_mobile/core/utils/working_clock.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/logic/working_since.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/blocks/logic/session_activity.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_preview_globe.dart';

class TerminalChatHeader extends StatelessWidget {
  const TerminalChatHeader({super.key, required this.onFind, required this.onKill, required this.frost});

  static DateTime? workingSinceOf(BuildContext context) {
    List<SessionModel> sessions;
    try {
      sessions = context.read<SessionsCubit>().sessions;
    } on ProviderNotFoundException {
      sessions = const [];
    }
    return workingSince(
      sessions: sessions,
      sessionId: context.read<SessionCommandCubit>().sessionId,
      blocks: context.read<BlocksCubit>().blocks,
    );
  }

  static const double barHeight = 52;
  static const double buttonSize = GlassMetrics.sheetHeaderButton;
  static const double side = 12;
  static const Key bandKey = ValueKey('chat-header-band');
  static const Key backKey = ValueKey('chat-header-back');
  static const Key capsuleKey = ValueKey('chat-header-capsule');
  static const Key activityKey = ValueKey('chat-header-activity');

  static double heightOf(BuildContext context) => MediaQuery.paddingOf(context).top + barHeight;

  final VoidCallback onFind;
  final VoidCallback onKill;
  final ValueListenable<double> frost;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final safeTop = MediaQuery.paddingOf(context).top;
    final args = context.read<TerminalCubit>().args;
    return SizedBox(
      height: safeTop + barHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: frost,
            builder: (context, visibility, _) => FrostedBand(key: bandKey, visibility: visibility, hairline: true),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(side, safeTop, side, 0),
            child: GlassScope(
              variant: GlassVariant.regular,
              size: buttonSize,
              child: Row(
                children: [
                  GlassButton.icon(
                    key: backKey,
                    icon: Icons.arrow_back_ios_new_rounded,
                    semanticLabel: 'Back',
                    foreground: skin.textPrimary,
                    diameter: buttonSize,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _TitleBlock(onKill: onKill)),
                  if (!args.shellOnly) ...[const SizedBox(width: 8), _TrailingCapsule(onFind: onFind)],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.onKill});

  final VoidCallback onKill;

  void _showActions(BuildContext context) {
    final skin = context.skin;
    final terminal = context.read<TerminalCubit>();
    final args = terminal.args;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Smaller text'), onTap: () => terminal.zoom(-1)),
            ListTile(title: const Text('Larger text'), onTap: () => terminal.zoom(1)),
            if (!args.shellOnly)
              BlocProvider.value(
                value: context.read<PreviewCubit>(),
                child: TerminalPreviewGlobe(sessionId: args.sessionId, title: args.title, previewUrl: args.previewUrl),
              ),
            ListTile(
              title: Text(args.shellOnly ? 'Close shell' : 'Kill session', style: TextStyle(color: skin.red)),
              onTap: () {
                Navigator.pop(context);
                onKill();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final terminal = context.read<TerminalCubit>();
    final args = terminal.args;
    final live = terminal.status == MuxStatus.open;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showActions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 7,
            children: [
              Flexible(
                child: Text(
                  args.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.style17Bold.copyWith(color: skin.textPrimary, height: 1.2),
                ),
              ),
              Semantics(
                label: live ? 'live' : 'disconnected',
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.base,
                  curve: AppMotion.easeOut,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: live ? skin.green : skin.textTertiary),
                ),
              ),
            ],
          ),
          Text(
            [
              args.harness ?? (args.shellOnly ? 'shell' : 'agent'),
              if (args.projectName != null) args.projectName!,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TrailingCapsule extends StatelessWidget {
  const _TrailingCapsule({required this.onFind});

  static const double _slot = 34;

  final VoidCallback onFind;

  Widget _reveal(Widget child, Animation<double> animation) => FadeTransition(
    opacity: animation,
    child: SizeTransition(sizeFactor: animation, axis: Axis.horizontal, alignment: Alignment.centerLeft, child: child),
  );

  Widget _swap(Widget child, Animation<double> animation) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(scale: Tween<double>(begin: 0.8, end: 1).animate(animation), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final terminal = context.read<TerminalCubit>();
    final still = MediaQuery.disableAnimationsOf(context);
    return GlassSurface(
      key: TerminalChatHeader.capsuleKey,
      kind: GlassShapeKind.capsule,
      size: TerminalChatHeader.buttonSize,
      pressable: true,
      child: Theme(
        data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: TerminalChatHeader.buttonSize,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 2),
              child: BlocBuilder<SessionViewCubit, SessionViewState>(
                buildWhen: (previous, current) => previous != current,
                builder: (context, state) {
                  final blocks = context.read<SessionViewCubit>().mode == SessionViewMode.blocks;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SessionActivityPill(stopped: terminal.notFound),
                      const SizedBox(width: 2),
                      AnimatedSwitcher(
                        duration: still ? Duration.zero : AppMotion.control,
                        switchInCurve: AppMotion.controlCurve,
                        switchOutCurve: AppMotion.controlCurve.flipped,
                        transitionBuilder: _reveal,
                        child: blocks
                            ? IconButton(
                                key: const ValueKey('find'),
                                tooltip: 'Find in blocks',
                                onPressed: onFind,
                                constraints: const BoxConstraints.tightFor(width: _slot, height: _slot),
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.search_rounded, size: 19, color: skin.textSecondary),
                              )
                            : const SizedBox.shrink(key: ValueKey('no-find')),
                      ),
                      Semantics(
                        button: true,
                        label: blocks ? 'Show raw terminal' : 'Show blocks',
                        child: IconButton(
                          onPressed: context.read<SessionViewCubit>().toggle,
                          constraints: const BoxConstraints.tightFor(width: _slot, height: _slot),
                          padding: EdgeInsets.zero,
                          icon: AnimatedSwitcher(
                            duration: still ? Duration.zero : AppMotion.chatActionSwap,
                            transitionBuilder: _swap,
                            child: Icon(
                              blocks ? Icons.terminal_rounded : Icons.view_agenda_outlined,
                              key: ValueKey(blocks),
                              size: 18,
                              color: skin.blue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionActivityPill extends StatefulWidget {
  const _SessionActivityPill({required this.stopped});

  final bool stopped;

  @override
  State<_SessionActivityPill> createState() => _SessionActivityPillState();
}

class _SessionActivityPillState extends State<_SessionActivityPill> {
  @override
  void initState() {
    super.initState();
    WorkingClock.shared.addListener(_tick);
  }

  void _tick() {
    if (mounted && sessionIsWorking(context.read<SessionCommandCubit>().activity)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WorkingClock.shared.removeListener(_tick);
    super.dispose();
  }

  String _elapsed(BuildContext context) {
    final since = TerminalChatHeader.workingSinceOf(context);
    if (since == null) return 'Working';
    return turnElapsed(WorkingClock.shared.value.difference(since));
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionCommandCubit, SessionCommandState>(
    buildWhen: (previous, current) => previous != current,
    builder: (context, state) {
      final skin = context.skin;
      final activity = context.read<SessionCommandCubit>().activity;
      final busy = sessionIsWorking(activity);
      final waiting = sessionIsWaiting(activity);
      final ink = widget.stopped
          ? skin.red
          : busy
          ? skin.orange
          : waiting
          ? skin.amber
          : skin.green;
      final still = MediaQuery.disableAnimationsOf(context);
      return AnimatedContainer(
        key: TerminalChatHeader.activityKey,
        duration: still ? Duration.zero : AppMotion.base,
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: widget.stopped
              ? skin.tintRed
              : busy
              ? skin.tintOrange
              : waiting
              ? skin.tintAmber
              : skin.tintGreen,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedSize(
          duration: still ? Duration.zero : AppMotion.control,
          curve: AppMotion.controlCurve,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
              Text(
                widget.stopped
                    ? 'Stopped'
                    : busy
                    ? _elapsed(context)
                    : waiting
                    ? 'Waiting'
                    : 'Idle',
                style: AppTextStyle.style11SemiBold.copyWith(color: ink),
              ),
            ],
          ),
        ),
      );
    },
  );
}
