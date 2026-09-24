import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/session_command_row.dart';
import 'package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:operator_mobile/feature/dictation/ui/voice_strip.dart';
import 'package:operator_mobile/feature/dictation/voice_types.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/terminal/logic/model_command.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_model_chip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/suggested_prompt_bubble.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

class TerminalComposer extends StatefulWidget {
  const TerminalComposer({super.key});

  static const Key capsuleKey = ValueKey('terminal-composer-capsule');
  static const double restHeight = 48;
  static const double cardRadius = 26;
  static const int maxLines = 5;

  @override
  State<TerminalComposer> createState() => _TerminalComposerState();
}

class _TerminalComposerState extends State<TerminalComposer> {
  static const double _buttonInset = 6;
  static const double _buttonZone = _buttonInset * 2 + ComposerActionButton.size;
  static const double _textInset = 18;
  static const double _cardTop = 14;
  static const double _measureSlack = 4;
  static const double _lineSpacing = 1.3;

  late final VoiceInputCubit _voice = sl<VoiceInputCubit>(
    param1: _appendTranscript,
  );
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: _voice.onAppBackgrounded,
    onPause: _voice.onAppBackgrounded,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'terminal-composer');
  bool _pickerOpen = false;
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  double _measuredLineHeight = 0;

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
    _focus.dispose();
    unawaited(_voice.close());
    super.dispose();
  }

  void _send(BuildContext context, TerminalCubit cubit) {
    final command = cubit.args.shellOnly || cubit.sendTarget == SendTarget.terminal
        ? null
        : parseModelCommand(cubit.composer.text);
    if (command == null) {
      unawaited(cubit.send());
      return;
    }
    cubit.composer.clear();
    final label = command.label;
    if (label == null) {
      showModelPicker(context, harness: cubit.args.harness);
      return;
    }
    unawaited(switchModel(context, label));
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

  void _stop(SessionCommandCubit commands) {
    Haptics.tap();
    unawaited(commands.run('stop'));
  }

  Future<void> _openModelPicker(BuildContext context, String? harness) async {
    setState(() => _pickerOpen = true);
    await showModelPicker(context, harness: harness);
    if (!mounted) return;
    setState(() => _pickerOpen = false);
    _focus.requestFocus();
  }

  bool _expands(String text, TextStyle style, TextScaler scaler, double width) {
    if (!(_focus.hasFocus || _pickerOpen) || text.isEmpty) return false;
    if (text.contains('\n')) return true;
    if (width <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      strutStyle: StrutStyle.fromTextStyle(style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines >= 2;
  }

  double _lineHeight(TextStyle style, TextScaler scaler) {
    if (style == _measuredStyle && scaler == _measuredScaler) return _measuredLineHeight;
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      strutStyle: StrutStyle.fromTextStyle(style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    _measuredStyle = style;
    _measuredScaler = scaler;
    _measuredLineHeight = height;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();

    return BlocProvider<VoiceInputCubit>.value(
      value: _voice,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VoiceStrip(),
          if (!cubit.args.shellOnly) const SlashCommandMenu(),
          if (!cubit.args.shellOnly) const SuggestedPromptBubble(),
          BlocBuilder<TerminalCubit, TerminalState>(
            buildWhen: (previous, current) => current is TerminalReadyState,
            builder: (context, state) => LayoutBuilder(
              builder: (context, constraints) => ListenableBuilder(
                listenable: Listenable.merge([_focus, cubit.composer]),
                builder: (context, _) => BlocBuilder<SessionCommandCubit, SessionCommandState>(
                  builder: (context, _) => BlocBuilder<VoiceInputCubit, VoiceInputState>(
                    builder: (context, _) => _capsule(context, cubit, constraints.maxWidth),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsule(BuildContext context, TerminalCubit cubit, double width) {
    final skin = context.skin;
    final shellOnly = cubit.args.shellOnly;
    final toTerminal = cubit.sendTarget == SendTarget.terminal;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.composerMorph;
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppTextStyle.style17Regular.copyWith(color: skin.textPrimary, height: _lineSpacing);
    final leading = shellOnly ? _textInset : _buttonZone;
    final text = cubit.composer.text;
    final hasText = text.trim().isNotEmpty;
    final commands = context.read<SessionCommandCubit>();
    final voice = context.read<VoiceInputCubit>();
    final recording = voice.phase == VoiceState.starting || voice.phase == VoiceState.recording;
    final showStop = composerShowsStop(hasText: hasText, canStop: !shellOnly && commands.enabled('stop'));
    final trailing = _buttonZone + (showStop ? ComposerActionButton.size + ComposerStopButton.gap : 0);
    final expanded = _expands(text, style, scaler, width - leading - trailing - _measureSlack);
    final lineHeight = _lineHeight(style, scaler);

    final body = Stack(
      children: [
        Padding(
          padding: expanded
              ? const EdgeInsets.fromLTRB(_textInset, _cardTop, _textInset, _buttonZone)
              : EdgeInsets.only(left: leading, right: trailing),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: expanded ? lineHeight : TerminalComposer.restHeight),
            child: Align(
              alignment: expanded ? Alignment.topLeft : Alignment.centerLeft,
              child: SizedBox(
                height: expanded ? null : lineHeight,
                child: ClipRect(
                  child: Stack(
                    children: [
                      TextField(
                        controller: cubit.composer,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: TerminalComposer.maxLines,
                        keyboardType: TextInputType.multiline,
                        style: style,
                        cursorColor: skin.accent,
                        decoration: InputDecoration.collapsed(
                          hintText: toTerminal ? 'Send to terminal...' : 'Message the agent...',
                          hintStyle: style.copyWith(color: skin.textTertiary),
                          hintMaxLines: 1,
                        ),
                      ),
                      const TerminalComposerDraftHint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!shellOnly)
          Positioned(
            left: _buttonInset,
            bottom: _buttonInset,
            child: SizedBox.square(
              dimension: ComposerActionButton.size,
              child: IconButton(
                style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                tooltip: 'Session actions',
                onPressed: () => _openActions(context),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.bolt_rounded, size: 21, color: skin.textSecondary),
              ),
            ),
          ),
        Positioned(
          left: leading,
          right: trailing,
          bottom: _buttonInset,
          height: ComposerActionButton.size,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeOut,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: expanded
                ? _Toolbar(
                    key: const ValueKey('composer-toolbar'),
                    harness: cubit.args.harness,
                    showModel: !shellOnly && !toTerminal,
                    showHideKeyboard: keyboardUp,
                    onModel: () => unawaited(_openModelPicker(context, cubit.args.harness)),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Positioned(
          right: _buttonInset,
          bottom: _buttonInset,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ComposerStopButton(visible: showStop, onStop: () => _stop(commands)),
              ComposerActionButton(
                action: composerActionFor(hasText: hasText, recording: recording),
                onSend: cubit.sending ? null : () => _send(context, cubit),
              ),
            ],
          ),
        ),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: expanded ? TerminalComposer.cardRadius : TerminalComposer.restHeight / 2),
      duration: duration,
      curve: AppMotion.easeOut,
      builder: (context, radius, child) => GlassSurface(
        key: TerminalComposer.capsuleKey,
        kind: !expanded && radius == TerminalComposer.restHeight / 2
            ? GlassShapeKind.capsule
            : GlassShapeKind.roundedRect,
        size: TerminalComposer.restHeight,
        radius: radius,
        child: child!,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: reduceMotion
            ? body
            : AnimatedSize(
                duration: duration,
                curve: AppMotion.easeOut,
                alignment: Alignment.bottomCenter,
                child: body,
              ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    super.key,
    required this.harness,
    required this.showModel,
    required this.showHideKeyboard,
    required this.onModel,
  });

  final String? harness;
  final bool showModel;
  final bool showHideKeyboard;
  final VoidCallback onModel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: showModel ? ComposerModelChip(harness: harness, onTap: onModel) : const SizedBox.shrink(),
          ),
        ),
        if (showHideKeyboard)
          IconButton(
            style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            tooltip: 'Hide keyboard',
            onPressed: () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: skin.textTertiary),
          ),
      ],
    );
  }
}
