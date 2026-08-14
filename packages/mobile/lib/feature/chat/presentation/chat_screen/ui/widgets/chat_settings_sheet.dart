import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/params/set_config_option_params.dart';

const List<({String id, String label, String hint})> kApprovalModes = [
  (
    id: 'default',
    label: 'Default',
    hint: 'The worktree is the safety boundary',
  ),
  (
    id: 'accept-edits',
    label: 'Ask outside worktree',
    hint: 'Edits here are allowed; anything else asks',
  ),
  (
    id: 'auto',
    label: 'Ask when unsure',
    hint: 'The agent decides when to check with you',
  ),
  (
    id: 'bypass-permissions',
    label: 'Never ask',
    hint: 'No approvals or sandbox prompts',
  ),
];

Future<void> showChatSettingsSheet(
  BuildContext context, {
  required ConversationSnapshotModel snapshot,
  required List<ChatModelModel> models,
  required List<ChatConfigOptionModel> options,
  required bool disabled,
  required void Function(TurnSettingsModel settings) onSettings,
  required void Function(SetConfigOptionParams params) onOption,
  String? error,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _ChatSettingsSheet(
      snapshot: snapshot,
      models: models,
      options: options,
      disabled: disabled,
      error: error,
      onSettings: onSettings,
      onOption: onOption,
    ),
  );
}

class _ChatSettingsSheet extends StatelessWidget {
  const _ChatSettingsSheet({
    required this.snapshot,
    required this.models,
    required this.options,
    required this.disabled,
    required this.onSettings,
    required this.onOption,
    this.error,
  });

  final ConversationSnapshotModel snapshot;
  final List<ChatModelModel> models;
  final List<ChatConfigOptionModel> options;
  final bool disabled;
  final String? error;
  final void Function(TurnSettingsModel settings) onSettings;
  final void Function(SetConfigOptionParams params) onOption;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final usesProviderOptions = snapshot.can('config_options');
    final selected = _selectedModel();
    final efforts = selected?.efforts ?? const <String>[];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Turn settings',
                        style: AppTextStyle.style17SemiBold,
                      ),
                      AppText(
                        'Changes apply to the next message.',
                        style: AppTextStyle.style11Regular.copyWith(
                          color: skin.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close, size: 20, color: skin.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                if (error != null)
                  Container(
                    padding: const EdgeInsets.all(11),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: skin.tintRed,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 14, color: skin.red),
                        const HorizontalSpace(8),
                        Expanded(
                          child: AppText(
                            error!,
                            style: AppTextStyle.style12Regular.copyWith(
                              color: skin.textSecondary,
                            ),
                            maxLines: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (snapshot.modelReroute != null)
                  Container(
                    padding: const EdgeInsets.all(11),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: skin.tintAmber,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Currently answered by ${snapshot.modelReroute!.toModel}',
                          style: AppTextStyle.style12SemiBold,
                          maxLines: 2,
                        ),
                        AppText(
                          '${snapshot.modelReroute!.fromModel == null ? '' : '${snapshot.modelReroute!.fromModel} was requested. '}'
                          '${snapshot.modelReroute!.reason ?? 'The provider selected a fallback model for this conversation.'}',
                          style: AppTextStyle.style11Regular.copyWith(
                            color: skin.textSecondary,
                          ),
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                if (!usesProviderOptions && models.isNotEmpty)
                  _Section(
                    icon: Icons.memory,
                    title: 'Model',
                    children: [
                      for (final model in models)
                        _Choice(
                          label: model.displayName ?? '',
                          hint:
                              model.description ??
                              (model.isDefault == true
                                  ? 'Provider default'
                                  : null),
                          selected: model.id == selected?.id,
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(
                              model: model.id,
                              approvalMode: snapshot.settings.approvalMode,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (!usesProviderOptions && efforts.isNotEmpty)
                  _Section(
                    icon: Icons.speed,
                    title: 'Reasoning effort',
                    children: [
                      for (final effort in efforts)
                        _Choice(
                          label:
                              '${effort[0].toUpperCase()}${effort.substring(1)}',
                          selected:
                              effort ==
                              (snapshot.settings.reasoningEffort ??
                                  selected?.defaultEffort),
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(
                              model: snapshot.settings.model,
                              reasoningEffort: effort,
                              approvalMode: snapshot.settings.approvalMode,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (!usesProviderOptions)
                  _Section(
                    icon: Icons.shield_outlined,
                    title: 'Approvals',
                    children: [
                      for (final mode in kApprovalModes)
                        _Choice(
                          label: mode.label,
                          hint: mode.hint,
                          selected:
                              mode.id ==
                              (snapshot.settings.approvalMode ?? 'default'),
                          enabled: !disabled,
                          onTap: () => onSettings(
                            TurnSettingsModel(
                              model: snapshot.settings.model,
                              reasoningEffort:
                                  snapshot.settings.reasoningEffort,
                              approvalMode: mode.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                for (final option in options)
                  _Section(
                    icon: _optionIcon(option),
                    title: option.name ?? '',
                    description: option.description,
                    children: option.type == 'boolean'
                        ? [
                            Row(
                              children: [
                                Expanded(
                                  child: AppText(
                                    option.currentBoolean == true
                                        ? 'On'
                                        : 'Off',
                                    style: AppTextStyle.style13Regular,
                                  ),
                                ),
                                Switch(
                                  value: option.currentBoolean == true,
                                  activeThumbColor: skin.blue,
                                  onChanged: disabled
                                      ? null
                                      : (enabled) => onOption(
                                          SetConfigOptionParams(
                                            optionId: option.id ?? '',
                                            enabled: enabled,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ]
                        : _groupedChoices(option),
                  ),
                if (usesProviderOptions && options.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: AppText(
                      'The provider has not advertised any turn controls yet.',
                      style: AppTextStyle.style13Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ChatModelModel? _selectedModel() {
    for (final model in models) {
      if (model.id == snapshot.settings.model) return model;
    }
    for (final model in models) {
      if (model.isDefault == true) return model;
    }
    return null;
  }

  List<Widget> _groupedChoices(ChatConfigOptionModel option) {
    final groups = <String, List<ChatConfigChoiceModel>>{};
    for (final choice in option.choices ?? const <ChatConfigChoiceModel>[]) {
      groups
          .putIfAbsent(choice.groupName ?? choice.group ?? '', () => [])
          .add(choice);
    }
    return [
      for (final entry in groups.entries) ...[
        if (entry.key.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: AppText(entry.key, style: AppTextStyle.style10Bold),
          ),
        for (final choice in entry.value)
          _Choice(
            label: choice.name ?? '',
            hint: choice.description,
            selected: choice.value == option.currentValue,
            enabled: !disabled,
            onTap: () => onOption(
              SetConfigOptionParams(
                optionId: option.id ?? '',
                value: choice.value,
              ),
            ),
          ),
      ],
    ];
  }

  IconData _optionIcon(ChatConfigOptionModel option) {
    if (option.id == 'fast') return Icons.bolt;
    if (option.id == 'agent') return Icons.person_outline;
    return switch (option.category) {
      'model' => Icons.memory,
      'thought_level' => Icons.speed,
      'mode' => Icons.shield_outlined,
      _ => Icons.tune,
    };
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: skin.textTertiary),
              const HorizontalSpace(7),
              AppText(title, style: AppTextStyle.style12Bold),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                description!,
                style: AppTextStyle.style11Regular.copyWith(
                  color: skin.textTertiary,
                ),
                maxLines: 3,
              ),
            ),
          const VerticalSpace(8),
          Container(
            decoration: BoxDecoration(
              color: skin.bgElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    label,
                    style: AppTextStyle.style13SemiBold.copyWith(
                      color: selected ? skin.blue : skin.textPrimary,
                    ),
                  ),
                  if (hint != null)
                    AppText(
                      hint!,
                      style: AppTextStyle.style11Regular.copyWith(
                        color: skin.textTertiary,
                      ),
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 16, color: skin.blue),
          ],
        ),
      ),
    );
  }
}
