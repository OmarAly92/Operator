import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_status_line.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class DesktopStatusLine extends StatefulWidget {
  const DesktopStatusLine({
    super.key,
    required this.fetchedAt,
    required this.onTap,
    this.onRePair,
    this.clock = DateTime.now,
  });

  static const Key tapKey = ValueKey('desktop-status-line');

  final DateTime? fetchedAt;
  final VoidCallback onTap;
  final VoidCallback? onRePair;
  final DateTime Function() clock;

  @override
  State<DesktopStatusLine> createState() => _DesktopStatusLineState();
}

class _DesktopStatusLineState extends State<DesktopStatusLine> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(AppMotion.statusLineTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<ConnectionCubit, AppConnectionState>(
      builder: (context, state) {
        final line = connectionStatusLine(state, now: widget.clock(), fetchedAt: widget.fetchedAt);
        final color = switch (line.tone) {
          StatusTone.neutral => skin.textTertiary,
          StatusTone.attention => skin.amber,
          StatusTone.danger => skin.red,
        };
        final name = state.desktopName;
        final action = state is ConnectionAuthFailedState ? widget.onRePair ?? widget.onTap : widget.onTap;
        return Semantics(
          button: true,
          label: '${name ?? 'Desktop'}, ${line.text}',
          excludeSemantics: true,
          child: GestureDetector(
            key: DesktopStatusLine.tapKey,
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.select();
              action();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.busy) ...[
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(strokeWidth: 1.4, color: skin.textTertiary),
                  ),
                  const HorizontalSpace(5),
                ],
                if (name != null) ...[
                  Flexible(
                    child: AppText(
                      name,
                      style: AppTextStyle.style12SemiBold.copyWith(color: skin.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppText(' · ', style: AppTextStyle.style12Regular.copyWith(color: skin.textFaint)),
                ],
                Flexible(
                  child: AppText(
                    line.text,
                    style: AppTextStyle.style12Medium.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const HorizontalSpace(2),
                Icon(Icons.expand_more_rounded, size: 14, color: skin.textFaint),
              ],
            ),
          ),
        );
      },
    );
  }
}
