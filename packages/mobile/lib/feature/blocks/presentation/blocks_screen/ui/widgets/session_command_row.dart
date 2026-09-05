import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
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
  const SessionCommandRow({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SessionCommandCubit>();
    final phases = cubit.phases;
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
                phase: phases[command],
                onTap: () => _onTap(context, cubit, command),
              ),
            ),
        ],
      ),
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
        builder: (_) => BlocProvider.value(value: cubit, child: const ModelPickerSheet()),
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
  });

  final String label;
  final bool enabled;
  final CommandPhase? phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final foreground = enabled ? null : skin.textFaint;
    final Widget? indicator = switch (phase) {
      CommandPhase.sending => SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: skin.textTertiary),
      ),
      CommandPhase.sent => Icon(Icons.check, size: 13, color: skin.textTertiary),
      CommandPhase.confirmed => Icon(Icons.check, size: 13, color: skin.green),
      CommandPhase.unconfirmed => Icon(Icons.error_outline, size: 13, color: skin.attention),
      _ => null,
    };

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: skin.bgElevated,
            border: Border.all(color: skin.borderDefault),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              AppText(label, style: AppTextStyle.mono13Regular.copyWith(color: foreground)),
              ?indicator,
            ],
          ),
        ),
      ),
    );
  }
}
