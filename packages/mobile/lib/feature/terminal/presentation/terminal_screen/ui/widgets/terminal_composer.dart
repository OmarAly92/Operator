import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/ui/mic_key.dart';
import 'package:operator_mobile/feature/chat/voice/ui/voice_strip.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalComposer extends StatefulWidget {
  const TerminalComposer({super.key});

  @override
  State<TerminalComposer> createState() => _TerminalComposerState();
}

class _TerminalComposerState extends State<TerminalComposer> {
  late final VoiceInputCubit _voice = sl<VoiceInputCubit>(
    param1: _appendTranscript,
  );
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: _voice.onAppBackgrounded,
    onPause: _voice.onAppBackgrounded,
  );

  void _appendTranscript(String spoken) {
    final composer = context.read<TerminalCubit>().composer;
    composer.text = appendTranscript(composer.text, spoken);
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    Haptics.success();
  }

  @override
  void initState() {
    super.initState();
    _lifecycle.hashCode;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_voice.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return BlocProvider<VoiceInputCubit>.value(
      value: _voice,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VoiceStrip(),
          BlocBuilder<TerminalCubit, TerminalState>(
            buildWhen: (previous, current) => current is TerminalReadyState,
            builder: (context, state) {
              final toTerminal = cubit.sendTarget == SendTarget.terminal;
              final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;

              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 7),
                child: Row(
                  spacing: 7,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: 40,
                          maxHeight: 108,
                        ),
                        padding: const EdgeInsets.only(left: 11, right: 4),
                        decoration: BoxDecoration(
                          color: skin.bgElevated,
                          border: Border.all(color: skin.borderDefault),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: cubit.composer,
                                maxLines: null,
                                style: AppTextStyle.style15Regular.copyWith(
                                  color: skin.textPrimary,
                                ),
                                cursorColor: skin.blue,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  hintText: toTerminal
                                      ? 'Send to terminal...'
                                      : 'Message the agent...',
                                  hintStyle: AppTextStyle.style15Regular
                                      .copyWith(color: skin.textFaint),
                                ),
                              ),
                            ),
                            if (!cubit.args.shellOnly)
                              IconButton(
                                tooltip: toTerminal
                                    ? 'Switch to chat'
                                    : 'Switch to terminal',
                                onPressed: () => cubit.setSendTarget(
                                  toTerminal
                                      ? SendTarget.agent
                                      : SendTarget.terminal,
                                ),
                                icon: Icon(
                                  toTerminal
                                      ? Icons.chat_bubble_outline
                                      : Icons.terminal,
                                  size: 15,
                                  color: toTerminal
                                      ? skin.textTertiary
                                      : skin.blue,
                                ),
                              ),
                            if (keyboardUp)
                              IconButton(
                                tooltip: 'Hide keyboard',
                                onPressed: () => SystemChannels.textInput
                                    .invokeMethod<void>('TextInput.hide'),
                                icon: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: skin.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const MicKey(),
                    const HorizontalSpace(7),
                    Semantics(
                      button: true,
                      label: 'Send',
                      child: InkWell(
                        onTap: cubit.sending ? null : cubit.send,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: skin.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.send,
                            size: 17,
                            color: skin.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
