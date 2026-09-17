import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_row.dart';

const int _kMaxVisibleRows = 6;

class SlashCommandMenu extends StatelessWidget {
  const SlashCommandMenu({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SlashMenuCubit, SlashMenuState>(
    buildWhen: (previous, current) => current is SlashMenuChangedState,
    builder: (context, state) {
      final cubit = context.read<SlashMenuCubit>();
      if (!cubit.open) return const SizedBox.shrink();
      final skin = context.skin;
      final rows = cubit.matches.take(_kMaxVisibleRows).toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Container(
          decoration: BoxDecoration(
            color: skin.bgElevated,
            border: Border.all(color: skin.borderDefault),
            borderRadius: BorderRadius.circular(11),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final command in rows)
                SlashCommandRow(
                  name: command.name ?? '',
                  description: command.description ?? '',
                  source: command.source ?? '',
                  onTap: () {
                    Haptics.select();
                    cubit.pick(command);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
