import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

/// Placeholder labels shown before the daemon has ever reported its own
/// model list for the harness — the first real response replaces these.
const _kPlaceholderModels = {
  'claude-code': ['sonnet', 'opus', 'haiku'],
  'codex': ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.5'],
};

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<SessionCommandCubit>();
    var models = cubit.models;
    if (models.isEmpty) {
      final harness = context.read<TerminalCubit>().args.harness;
      models = _kPlaceholderModels[harness] ?? const [];
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final model in models)
            ListTile(
              title: AppText(model, style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary)),
              onTap: () {
                Navigator.of(context).pop();
                cubit.run('model', model: model);
              },
            ),
        ],
      ),
    );
  }
}
