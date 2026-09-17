import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';

/// Placeholder labels shown before the daemon has ever reported its own
/// model list for the harness — the first real response replaces these.
const _kPlaceholderModels = {
  'claude-code': ['sonnet', 'opus', 'haiku'],
  'codex': ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.5'],
};

void showModelPicker(BuildContext context, {String? harness}) {
  final cubit = context.read<SessionCommandCubit>();
  if (!cubit.enabled('model')) {
    final reason = cubit.disabledReason('model');
    if (reason != null) context.showSnackBar(reason);
    return;
  }
  Haptics.tap();
  cubit.fetchModels();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => BlocProvider.value(value: cubit, child: ModelPickerSheet(harness: harness)),
  );
}

Future<void> switchModel(BuildContext context, String label) async {
  final cubit = context.read<SessionCommandCubit>();
  if (!cubit.enabled('model')) {
    final reason = cubit.disabledReason('model');
    if (reason != null) context.showSnackBar(reason);
    return;
  }
  await cubit.run('model', model: label);
  if (!context.mounted || cubit.isClosed) return;
  if (cubit.state.phases['model'] == CommandPhase.idle) {
    final offered = cubit.models.isEmpty ? '' : ' Try: ${cubit.models.join(', ')}';
    context.showSnackBar('Could not switch to $label.$offered');
  }
}

class ModelPickerSheet extends StatelessWidget {
  const ModelPickerSheet({super.key, this.harness});

  final String? harness;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SafeArea(
      child: BlocBuilder<SessionCommandCubit, SessionCommandState>(
        buildWhen: (previous, current) =>
            previous.modelOptions != current.modelOptions ||
            previous.modelsLoading != current.modelsLoading ||
            previous.currentModel != current.currentModel,
        builder: (context, state) {
          final cubit = context.read<SessionCommandCubit>();
          final options = state.modelOptions.isNotEmpty
              ? state.modelOptions
              : [
                  for (final label in cubit.models.isNotEmpty ? cubit.models : _kPlaceholderModels[harness] ?? const <String>[])
                    SessionModelOptionModel(label: label, current: label == state.currentModel),
                ];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText('Model', style: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary)),
                          AppText(
                            'Applies to this session only',
                            style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    if (state.modelsLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: skin.textTertiary),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    for (final option in options)
                      _ModelRow(
                        option: option,
                        onTap: () {
                          final label = option.label;
                          if (label == null) return;
                          Navigator.of(context).pop();
                          if (option.current == true) return;
                          Haptics.select();
                          switchModel(context, label);
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.option, required this.onTap});

  final SessionModelOptionModel option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final current = option.current == true;
    final description = option.description ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: current ? skin.accentTint : skin.bgElevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: current ? skin.accent : skin.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        option.label ?? '',
                        style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary),
                      ),
                      if (description.isNotEmpty)
                        AppText(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.style11Regular.copyWith(color: skin.textTertiary),
                        ),
                    ],
                  ),
                ),
                if (current) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_rounded, size: 18, color: skin.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
