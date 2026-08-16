import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

class VoiceStrip extends StatelessWidget {
  const VoiceStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<VoiceInputCubit, VoiceInputState>(
      buildWhen: (previous, current) => current is VoiceInputReadyState,
      builder: (context, state) {
        final cubit = context.read<VoiceInputCubit>();
        final live =
            cubit.phase == VoiceState.starting ||
            cubit.phase == VoiceState.recording;
        final error = cubit.error;
        if (!live && error == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.mic, size: 12, color: skin.red),
              const HorizontalSpace(6),
              Expanded(
                child: AppText(
                  live
                      ? (cubit.partial.isNotEmpty
                            ? cubit.partial
                            : cubit.phase == VoiceState.starting
                            ? 'Keep holding…'
                            : 'Listening…')
                      : error!,
                  style: AppTextStyle.style12Regular.copyWith(
                    color: live ? skin.textSecondary : skin.red,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
