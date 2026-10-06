import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_toast.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_row.dart';

const double _kMaxMenuHeight = 300;
const double _kMenuRadius = 20;
const double _kGlassSize = 400;

class SlashCommandMenu extends StatelessWidget {
  const SlashCommandMenu({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SlashMenuCubit, SlashMenuState>(
    buildWhen: (previous, current) => current is SlashMenuChangedState,
    builder: (context, state) {
      final cubit = context.read<SlashMenuCubit>();
      if (!cubit.open) return const Disclosure(expanded: false, child: SizedBox.shrink());
      final rows = cubit.matches;
      return Disclosure(
        expanded: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassSurface(
            kind: GlassShapeKind.rect,
            radius: _kMenuRadius,
            size: _kGlassSize,
            child: ClipRSuperellipse(
              borderRadius: const BorderRadius.all(Radius.circular(_kMenuRadius)),
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _kMaxMenuHeight),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final command = rows[index];
                      final interactive = slashCommandNeedsDesktop(command);
                      return SlashCommandRow(
                        name: command.name ?? '',
                        description: command.description ?? '',
                        source: command.source ?? '',
                        interactive: interactive,
                        onTap: () {
                          Haptics.select();
                          if (command.name == 'model') {
                            cubit.composer.clear();
                            showModelPicker(context, harness: context.read<TerminalCubit>().args.harness);
                            return;
                          }
                          if (interactive) {
                            AppToast.show(
                              context,
                              message: 'Run /${command.name} on the desktop',
                              icon: Icons.desktop_windows_outlined,
                            );
                            return;
                          }
                          cubit.pick(command);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
