import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

/// Fixed count, fixed height, one flex each: the row is pixel-identical in every
/// state the screen can reach.
class TerminalKeyRow extends StatelessWidget {
  const TerminalKeyRow({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        spacing: 5,
        children: [
          for (final key in kControlKeys)
            Expanded(
              child: Semantics(
                button: true,
                label: key.hint,
                child: InkWell(
                  onTap: () {
                    Haptics.tap();
                    cubit.sendKey(key.sequence);
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
                    child: AppText(key.label, style: AppTextStyle.mono13Regular),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
