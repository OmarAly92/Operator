import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:operator_mobile/feature/dictation/ui/voice_strip.dart';
import 'package:operator_mobile/feature/dictation/voice_types.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/terminal/logic/model_command.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_model_chip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/slash_command_menu.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/suggested_prompt_bubble.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

class TerminalComposer extends StatefulWidget {
  const TerminalComposer({super.key});

  static const Key capsuleKey = ValueKey('terminal-composer-capsule');
  static const double restHeight = 48;
  static const double agentRestHeight = 84;
  static const double cardRadius = 26;
  static const int maxLines = 5;

  @override
  State<TerminalComposer> createState() => _TerminalComposerState();
}

class _TerminalComposerState extends State<TerminalComposer> {
  static const double _buttonInset = 6;
  static const double _buttonZone = _buttonInset * 2 + ComposerActionButton.size;
  static const double _textInset = 18;
  static const double _trailingInset = _textInset;
  static const double _trailingZone = _buttonInset + ComposerActionButton.size + _trailingInset;
  static const double _cardTop = 14;
  static const double _rowGap = 6;
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
    final command = cubit.args.shellOnly || cubit.attachments.isNotEmpty
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

  Future<void> _stop(SessionCommandCubit commands) async {
    if (commands.phases['stop'] == CommandPhase.sending) return;
    Haptics.tap();
    await commands.run('stop');
    if (!mounted || commands.isClosed) return;
    if (commands.phases['stop'] != CommandPhase.idle) return;
    Haptics.error();
    final refusal = commands.lastRefusal;
    if (refusal != null) context.showSnackBar(refusal);
  }

  Future<void> _openAddContext(BuildContext context) async {
    await showAddContextSheet(context);
    if (!mounted) return;
    _focus.requestFocus();
  }

  Future<void> _openModelPicker(BuildContext context, String? harness) async {
    await showModelPicker(context, harness: harness);
    if (!mounted) return;
    _focus.requestFocus();
  }

  bool _expands(String text, TextStyle style, TextScaler scaler, double width) {
    if (!_focus.hasFocus || text.isEmpty) return false;
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
                    builder: (context, _) => cubit.args.shellOnly
                        ? _shellCapsule(context, cubit, constraints.maxWidth)
                        : _agentCard(context, cubit),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shellCapsule(BuildContext context, TerminalCubit cubit, double width) {
    final skin = context.skin;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.composerMorph;
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppTextStyle.style17Regular.copyWith(color: skin.textPrimary, height: _lineSpacing);
    final text = cubit.composer.text;
    final hasText = text.trim().isNotEmpty;
    final voice = context.read<VoiceInputCubit>();
    final recording = voice.phase == VoiceState.starting || voice.phase == VoiceState.recording;
    final expanded = _expands(text, style, scaler, width - _textInset - _trailingZone - _measureSlack);
    final lineHeight = _lineHeight(style, scaler);

    final body = Stack(
      children: [
        Padding(
          padding: expanded
              ? const EdgeInsets.fromLTRB(_textInset, _cardTop, _textInset, _buttonZone)
              : const EdgeInsets.only(left: _textInset, right: _trailingZone),
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
                          hintText: 'Send to terminal...',
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
        Positioned(
          left: _textInset,
          right: _trailingZone,
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
                ? _Toolbar(key: const ValueKey('composer-toolbar'), showHideKeyboard: keyboardUp)
                : const SizedBox.shrink(),
          ),
        ),
        Positioned(
          right: _trailingInset,
          bottom: _buttonInset,
          child: ComposerActionButton(
            action: composerActionFor(hasText: hasText, recording: recording),
            onSend: cubit.sending ? null : () => _send(context, cubit),
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

  Widget _agentCard(BuildContext context, TerminalCubit cubit) {
    final skin = context.skin;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppMotion.composerMorph;
    final style = AppTextStyle.style17Regular.copyWith(color: skin.textPrimary, height: _lineSpacing);
    final commands = context.read<SessionCommandCubit>();
    final trailing = composerTrailingFor(hasContent: cubit.hasContent, canStop: commands.enabled('stop'));
    final editable = !cubit.sending;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cubit.attachments.isNotEmpty || cubit.attachmentNotice != null)
          ComposerAttachmentTray(
            attachments: cubit.attachments,
            notice: cubit.attachmentNotice,
            onRemove: editable ? cubit.removeAttachment : null,
            onDismissNotice: cubit.dismissAttachmentNotice,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_textInset, _cardTop, _textInset, 0),
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
                  hintText: 'Message the agent...',
                  hintStyle: style.copyWith(color: skin.textTertiary),
                  hintMaxLines: 1,
                ),
              ),
              const TerminalComposerDraftHint(),
            ],
          ),
        ),
        const SizedBox(height: _rowGap),
        Padding(
          padding: const EdgeInsets.fromLTRB(_buttonInset, 0, _buttonInset, _buttonInset),
          child: Row(
            children: [
              ComposerAddButton(onTap: editable ? () => unawaited(_openAddContext(context)) : null),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ComposerModelChip(
                    harness: cubit.args.harness,
                    onTap: () => unawaited(_openModelPicker(context, cubit.args.harness)),
                  ),
                ),
              ),
              if (keyboardUp)
                IconButton(
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  tooltip: 'Hide keyboard',
                  onPressed: () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: skin.textTertiary),
                ),
              const MicKey(quiet: true, size: ComposerActionButton.size),
              ComposerSendSlot(
                trailing: trailing,
                staging: cubit.staging,
                onSend: cubit.sending ? null : () => _send(context, cubit),
                onStop: commands.phases['stop'] == CommandPhase.sending ? null : () => unawaited(_stop(commands)),
              ),
            ],
          ),
        ),
      ],
    );

    return GlassSurface(
      key: TerminalComposer.capsuleKey,
      kind: GlassShapeKind.roundedRect,
      size: TerminalComposer.restHeight,
      radius: TerminalComposer.cardRadius,
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
  const _Toolbar({super.key, required this.showHideKeyboard});

  final bool showHideKeyboard;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Row(
      children: [
        const Spacer(),
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
