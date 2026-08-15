import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalStatusBar extends StatelessWidget {
  const TerminalStatusBar({super.key, required this.onKill, required this.onRestore});

  final VoidCallback onKill;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, state) {
        final grid = cubit.grid;
        final dead = cubit.notFound;
        final label = switch (cubit.status) {
          MuxStatus.connecting => 'connecting...',
          MuxStatus.open => 'live',
          MuxStatus.closed => 'disconnected',
          MuxStatus.error => 'error',
        };
        final color = switch (cubit.status) {
          MuxStatus.connecting => skin.attention,
          MuxStatus.open => skin.green,
          MuxStatus.closed => skin.textTertiary,
          MuxStatus.error => skin.red,
        };

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: skin.borderSubtle)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: AppText(
                  label,
                  style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                ),
              ),
              if (grid != null && !dead)
                AppText(
                  '${grid.cols}x${grid.rows}',
                  style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                ),
              if (!dead)
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: skin.bgElevated,
                    border: Border.all(color: skin.borderDefault),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Smaller text',
                        onPressed: () => cubit.zoom(-1),
                        icon: Icon(Icons.remove, size: 13, color: skin.textSecondary),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                        padding: EdgeInsets.zero,
                      ),
                      Container(width: 1, height: 24, color: skin.borderDefault),
                      IconButton(
                        tooltip: 'Larger text',
                        onPressed: () => cubit.zoom(1),
                        icon: Icon(Icons.add, size: 13, color: skin.textSecondary),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              if (dead && !cubit.args.shellOnly)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: InkWell(
                    onTap: cubit.restoring ? null : onRestore,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: skin.tintBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          Icon(Icons.restart_alt, size: 12, color: skin.blue),
                          AppText(
                            cubit.restoring ? 'Restoring...' : 'Restore',
                            style: AppTextStyle.style12Bold.copyWith(color: skin.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Semantics(
                    button: true,
                    label: cubit.args.shellOnly ? 'Close shell' : 'Kill session',
                    child: InkWell(
                      onTap: onKill,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: skin.tintRed,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          cubit.args.shellOnly ? Icons.close : Icons.delete_outline,
                          size: 14,
                          color: skin.red,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
