import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class SuggestedPromptBubble extends StatelessWidget {
  const SuggestedPromptBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, _) {
        final suggestion = cubit.suggestion;
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: cubit.composer,
          builder: (context, value, _) {
            final visible = suggestion != null && suggestion.isNotEmpty && value.text.isEmpty;
            return AnimatedSize(
              duration: AppMotion.slow,
              curve: AppMotion.easeOut,
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: AppMotion.slow,
                switchInCurve: AppMotion.easeOut,
                switchOutCurve: AppMotion.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.35),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: visible
                    ? _Bubble(
                        key: ValueKey(suggestion),
                        text: suggestion,
                        onAccept: () {
                          Haptics.select();
                          cubit.acceptSuggestion();
                        },
                        onDismiss: cubit.dismissSuggestion,
                      )
                    : const SizedBox(key: ValueKey('none'), width: double.infinity),
              ),
            );
          },
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.text,
    required this.onAccept,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PressScale(
          child: Material(
            color: skin.accentTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: skin.accent.withValues(alpha: 0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onAccept,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 13, color: skin.accent),
                    const HorizontalSpace(7),
                    Flexible(
                      child: AppText(
                        text,
                        style: AppTextStyle.style12p5Medium.copyWith(color: skin.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const HorizontalSpace(2),
                    Semantics(
                      button: true,
                      label: 'Dismiss suggestion',
                      child: InkWell(
                        onTap: onDismiss,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 13, color: skin.textTertiary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
