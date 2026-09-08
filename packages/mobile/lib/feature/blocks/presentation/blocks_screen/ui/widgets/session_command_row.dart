import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';

const _kCommands = ['stop', 'compact', 'model'];
const _kLabels = {'stop': 'Stop', 'compact': 'Compact', 'model': 'Model'};

/// Fixed count, fixed height, one flex each: the row is pixel-identical in
/// every session state the screen can reach — phase and enablement show
/// through colour and the trailing indicator only, never through layout.
class SessionCommandRow extends StatelessWidget {
  const SessionCommandRow({super.key, this.menu = false});

  final bool menu;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SessionCommandCubit>();
    // BlocBuilder, not a bare context.read: this widget is const, so Flutter
    // skips its element update when an ancestor rebuilds. Without a subscription
    // the phase indicators and the disabled styling freeze at their first values
    // while the session moves on underneath them.
    return BlocBuilder<SessionCommandCubit, SessionCommandState>(
      builder: (context, _) {
        final phases = cubit.phases;
        if (menu) {
          return Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                  child: Text(
                    'SESSION ACTIONS',
                    style: AppTextStyle.style11SemiBold.copyWith(
                      color: context.skin.textFaint,
                    ),
                  ),
                ),
                for (final command in _kCommands)
                  SizedBox(
                    height: 46,
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      tileColor: command == 'stop' && cubit.enabled(command)
                          ? context.skin.tintRed
                          : null,
                      textColor: !cubit.enabled(command)
                          ? context.skin.textFaint
                          : command == 'stop'
                          ? context.skin.red
                          : context.skin.textPrimary,
                      leading: Icon(
                        switch (command) {
                          'stop' => Icons.stop_circle_outlined,
                          'compact' => Icons.compress,
                          _ => Icons.tune,
                        },
                        size: 19,
                        color: !cubit.enabled(command)
                            ? context.skin.textFaint
                            : command == 'stop'
                            ? context.skin.red
                            : context.skin.textSecondary,
                      ),
                      title: Text(
                        _kLabels[command]!,
                        style: AppTextStyle.style15Medium,
                      ),
                      trailing: _phaseIndicator(context, phases[command]),
                      onTap: () {
                        if (cubit.enabled(command) && command != 'model') {
                          cubit.run(command);
                          Navigator.pop(context);
                        } else {
                          _onTap(context, cubit, command);
                        }
                      },
                    ),
                  ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            spacing: 5,
            children: [
              for (final command in _kCommands)
                Expanded(
                  child: SessionCommandButton(
                    label: _kLabels[command]!,
                    enabled: cubit.enabled(command),
                    dangerous: command == 'stop',
                    phase: phases[command],
                    onTap: () => _onTap(context, cubit, command),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _onTap(BuildContext context, SessionCommandCubit cubit, String command) {
    if (!cubit.enabled(command)) {
      final reason = cubit.disabledReason(command);
      if (reason != null) context.showSnackBar(reason);
      return;
    }
    if (command == 'model') {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const ModelPickerSheet()),
      );
      return;
    }
    cubit.run(command);
  }
}

class SessionCommandButton extends StatelessWidget {
  const SessionCommandButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.phase,
    required this.onTap,
    this.dangerous = false,
  });

  final String label;
  final bool enabled;
  final bool dangerous;
  final CommandPhase? phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final isDangerous = dangerous && enabled;
    final foreground = !enabled
        ? skin.textFaint
        : isDangerous
        ? skin.red
        : null;
    final indicator = _phaseIndicator(context, phase);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppConstants.radiusChip),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDangerous ? skin.tintRed : skin.bgElevated,
            border: Border.all(
              color: isDangerous ? skin.red : skin.borderDefault,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              AppText(
                label,
                style: AppTextStyle.mono13Regular.copyWith(color: foreground),
              ),
              ?indicator,
            ],
          ),
        ),
      ),
    );
  }
}

Widget? _phaseIndicator(BuildContext context, CommandPhase? phase) {
  final skin = context.skin;
  return switch (phase) {
    CommandPhase.sending => SizedBox(
      width: 11,
      height: 11,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: skin.textTertiary,
      ),
    ),
    CommandPhase.sent => Icon(Icons.check, size: 13, color: skin.textTertiary),
    CommandPhase.confirmed => Icon(Icons.check, size: 13, color: skin.green),
    CommandPhase.unconfirmed => Icon(
      Icons.error_outline,
      size: 13,
      color: skin.attention,
    ),
    _ => null,
  };
}
