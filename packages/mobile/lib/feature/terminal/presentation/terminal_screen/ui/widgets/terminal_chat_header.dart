import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_preview_globe.dart';

class TerminalChatHeader extends StatelessWidget {
  const TerminalChatHeader({
    super.key,
    required this.onFind,
    required this.onKill,
  });

  final VoidCallback onFind;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final terminal = context.read<TerminalCubit>();
    final args = terminal.args;
    return ColoredBox(
      color: skin.bgChrome,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
          child: Row(
            spacing: 8,
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: skin.textPrimary,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onLongPress: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Smaller text'),
                            onTap: () => terminal.zoom(-1),
                          ),
                          ListTile(
                            title: const Text('Larger text'),
                            onTap: () => terminal.zoom(1),
                          ),
                          if (!args.shellOnly)
                            BlocProvider.value(
                              value: context.read<PreviewCubit>(),
                              child: TerminalPreviewGlobe(
                                sessionId: args.sessionId,
                                title: args.title,
                                previewUrl: args.previewUrl,
                              ),
                            ),
                          ListTile(
                            title: Text(
                              args.shellOnly ? 'Close shell' : 'Kill session',
                              style: TextStyle(color: skin.red),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              onKill();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
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
                              style: AppTextStyle.style16SemiBold.copyWith(
                                color: skin.textPrimary,
                              ),
                            ),
                          ),
                          Semantics(
                            label: terminal.status == MuxStatus.open
                                ? 'live'
                                : 'disconnected',
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: terminal.status == MuxStatus.open
                                    ? skin.green
                                    : skin.textTertiary,
                              ),
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
                        style: AppTextStyle.mono11Regular.copyWith(
                          color: skin.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!args.shellOnly) ...[
                _SessionActivityPill(stopped: terminal.notFound),
                BlocBuilder<SessionViewCubit, SessionViewState>(
                  buildWhen: (previous, current) => previous != current,
                  builder: (context, state) {
                    final blocks =
                        context.read<SessionViewCubit>().mode ==
                        SessionViewMode.blocks;
                    return Row(
                      spacing: 8,
                      children: [
                        if (blocks)
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: 'Find in blocks',
                            onPressed: onFind,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.search,
                              size: 16,
                              color: skin.textSecondary,
                            ),
                          ),
                        Semantics(
                          button: true,
                          label: blocks ? 'Show raw terminal' : 'Show blocks',
                          child: IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: context.read<SessionViewCubit>().toggle,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              blocks
                                  ? Icons.terminal
                                  : Icons.view_agenda_outlined,
                              size: 18,
                              color: skin.blue,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<SessionCommandCubit>().activity == 'active') {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _elapsed(BuildContext context) {
    final groups = groupBlocksByTurn(
      context.read<BlocksCubit>().blocks,
      sessionActive: true,
    );
    final start = DateTime.tryParse(groups.lastOrNull?.startedAt ?? '');
    if (start == null) return 'Working';
    final seconds = DateTime.now()
        .difference(start)
        .inSeconds
        .clamp(0, 1 << 31);
    return seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SessionCommandCubit, SessionCommandState>(
        buildWhen: (previous, current) => previous != current,
        builder: (context, state) {
          final skin = context.skin;
          final activity = context.read<SessionCommandCubit>().activity;
          final busy = activity == 'active';
          final waiting = activity == 'blocked';
          final ink = widget.stopped
              ? skin.red
              : busy
              ? skin.orange
              : waiting
              ? skin.amber
              : skin.green;
          return Container(
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
          );
        },
      );
}
