import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalComposerDraftHint extends StatelessWidget {
  const TerminalComposerDraftHint({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    final skin = context.skin;
    final draft = cubit.draft;
    if (draft == null || draft.isEmpty) return const SizedBox.shrink();

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: cubit.composer,
      builder: (context, value, _) {
        if (value.text.isNotEmpty) return const SizedBox.shrink();
        return Positioned.fill(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  cubit.composer.text = draft;
                  cubit.composer.selection = TextSelection.collapsed(offset: draft.length);
                },
                child: AppText(
                  draft,
                  style: AppTextStyle.style15Regular.copyWith(color: skin.textFaint),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
