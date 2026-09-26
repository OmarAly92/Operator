import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/logic/permission_modes.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/permission_mode_cubit.dart';

class PermissionModeRow extends StatelessWidget {
  const PermissionModeRow({super.key});

  static const Key rowKey = ValueKey('permission-mode-row');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<PermissionModeCubit, PermissionModeState>(
      builder: (context, state) {
        if (!state.supported) return const SizedBox.shrink();
        final error = state.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            SettingsGroup(
              children: [
                SettingsRow(
                  key: rowKey,
                  icon: Icons.shield_outlined,
                  label: 'Permission',
                  value: permissionModeLabel(state.pending ?? state.mode),
                  loading: state.pending != null,
                  onTap: () => AppSheet.of(context).push(permissionModePage()),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(error, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
              ),
          ],
        );
      },
    );
  }
}

AppSheetPage permissionModePage() => AppSheetPage(
  title: 'Permission',
  subtitle: 'How much the agent asks before it acts.',
  rows: (context, _) => const [PermissionModeList()],
);

class PermissionModeList extends StatelessWidget {
  const PermissionModeList({super.key});

  static const Key errorKey = ValueKey('permission-mode-error');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<PermissionModeCubit, PermissionModeState>(
      builder: (context, state) {
        final cubit = context.read<PermissionModeCubit>();
        final selected = state.pending ?? state.mode;
        final error = state.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            SettingsGroup(
              children: [
                for (final mode in kPermissionModes)
                  _PermissionModeOption(
                    key: ValueKey('permission-mode-$mode'),
                    mode: mode,
                    selected: mode == selected && state.pending == null,
                    busy: state.pending == mode,
                    restarts: state.restarts(mode),
                    onTap: state.pending != null ? null : () => unawaited(_choose(context, cubit, mode)),
                  ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(error, key: errorKey, style: AppTextStyle.style12Medium.copyWith(color: skin.red)),
              ),
          ],
        );
      },
    );
  }
}

Future<void> _choose(BuildContext context, PermissionModeCubit cubit, String mode) async {
  Haptics.select();
  final sheet = AppSheet.of(context);
  if (await cubit.choose(mode) && context.mounted) sheet.pop();
}

class _PermissionModeOption extends StatelessWidget {
  const _PermissionModeOption({
    super.key,
    required this.mode,
    required this.selected,
    required this.busy,
    required this.restarts,
    required this.onTap,
  });

  final String mode;
  final bool selected;
  final bool busy;
  final bool restarts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      selected: selected,
      label: permissionModeLabel(mode),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(permissionModeLabel(mode), style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary)),
                      if (restarts)
                        Text(kPermissionRestartNote, style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
                    ],
                  ),
                ),
                if (busy)
                  SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent))
                else if (selected)
                  Icon(Icons.check_rounded, size: 18, color: skin.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
