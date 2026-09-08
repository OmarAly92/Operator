import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/press_scale.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/session_command_row.dart';
import 'package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:operator_mobile/feature/dictation/ui/voice_strip.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

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

  void _openActions(BuildContext context) {
    final commands = context.read<SessionCommandCubit>();
    final terminal = context.read<TerminalCubit>();
    final skin = context.skin;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close session actions',
      barrierColor: skin.scrim,
      pageBuilder: (dialogContext, _, animation) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              MediaQuery.viewInsetsOf(context).bottom + 72,
            ),
            child: Material(
              color: skin.bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: skin.borderDefault),
              ),
              child: BlocProvider.value(
                value: commands,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SessionCommandRow(menu: true),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.swap_horiz, size: 19),
                      title: Text(
                        terminal.sendTarget == SendTarget.agent
                            ? 'Send to terminal'
                            : 'Message the agent',
                      ),
                      onTap: () {
                        terminal.setSendTarget(
                          terminal.sendTarget == SendTarget.agent
                              ? SendTarget.terminal
                              : SendTarget.agent,
                        );
                        Navigator.pop(dialogContext);
                      },
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  spacing: 8,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: 40,
                          maxHeight: 108,
                        ),
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        decoration: BoxDecoration(
                          color: skin.bgElevated,
                          border: Border.all(color: skin.borderDefault),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  TextField(
                                    controller: cubit.composer,
                                    maxLines: null,
                                    style: AppTextStyle.style15Regular.copyWith(
                                      color: skin.textPrimary,
                                    ),
                                    cursorColor: skin.accent,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                      hintText: toTerminal
                                          ? 'Send to terminal...'
                                          : 'Message the agent...',
                                      hintStyle: AppTextStyle.style15Regular
                                          .copyWith(
                                            color: skin.textPrimary.withValues(
                                              alpha: 0.45,
                                            ),
                                          ),
                                    ),
                                  ),
                                  const TerminalComposerDraftHint(),
                                ],
                              ),
                            ),
                            if (!cubit.args.shellOnly)
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                tooltip: 'Session actions',
                                onPressed: () => _openActions(context),
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 40,
                                ),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.bolt_outlined,
                                  size: 19,
                                  color: skin.textTertiary,
                                ),
                              ),
                            if (keyboardUp)
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
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
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: cubit.composer,
                      builder: (context, value, _) => value.text.trim().isEmpty
                          ? const MicKey(prominent: true)
                          : PressScale(
                              scale: AppMotion.pressScaleSend,
                              child: Semantics(
                                button: true,
                                label: 'Send',
                                child: InkWell(
                                  onTap: cubit.sending ? null : cubit.send,
                                  borderRadius: BorderRadius.circular(23),
                                  child: Container(
                                    width: 46,
                                    height: 46,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: skin.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.arrow_upward,
                                      size: 22,
                                      color: skin.onAccent,
                                    ),
                                  ),
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
