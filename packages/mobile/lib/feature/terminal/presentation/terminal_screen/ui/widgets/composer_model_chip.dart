import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/blocks/logic/session_model_label.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';

class ComposerModelChip extends StatelessWidget {
  const ComposerModelChip({super.key, this.harness});

  static const String fallbackLabel = 'Default';

  final String? harness;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<BlocksCubit, BlocksState>(
      builder: (context, _) => BlocBuilder<SessionCommandCubit, SessionCommandState>(
        buildWhen: (previous, current) => previous.currentModel != current.currentModel,
        builder: (context, state) {
          final label =
              sessionModelLabel(currentModel: state.currentModel, blocks: context.read<BlocksCubit>().blocks) ??
              fallbackLabel;
          return Semantics(
            button: true,
            label: 'Model, $label',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showModelPicker(context, harness: harness),
              child: Container(
                height: 30,
                padding: const EdgeInsets.fromLTRB(7, 0, 8, 0),
                decoration: BoxDecoration(
                  color: skin.textPrimary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    AgentLogo(harness: harness, size: 16),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.style13Medium.copyWith(color: skin.textPrimary),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: skin.textTertiary),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
