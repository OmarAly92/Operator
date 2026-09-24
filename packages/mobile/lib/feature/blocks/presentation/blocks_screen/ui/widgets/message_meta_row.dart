import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

enum MessageMetaSide { user, assistant }

String messageTimeLabel(String? createdAt) {
  if (createdAt == null) return 'now';
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) return 'now';
  final local = parsed.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:${local.minute.toString().padLeft(2, '0')} $period';
}

class MessageMetaRow extends StatelessWidget {
  const MessageMetaRow({
    super.key,
    required this.id,
    required this.text,
    required this.createdAt,
    required this.side,
    this.timeKey,
    this.onLongPressTime,
    this.animateIn = false,
    this.interactive = true,
  });

  static const double copySize = 28;
  static const double copyIconSize = 13;
  static const double _iconInset = (copySize - copyIconSize) / 2;

  final String id;
  final String text;
  final String? createdAt;
  final MessageMetaSide side;
  final Key? timeKey;
  final VoidCallback? onLongPressTime;
  final bool animateIn;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final user = side == MessageMetaSide.user;
    final time = GestureDetector(
      key: timeKey,
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPressTime,
      child: AppText(
        messageTimeLabel(createdAt),
        style: AppTextStyle.mono10p5Regular.copyWith(color: context.skin.textTertiary),
      ),
    );
    final copy = IgnorePointer(
      ignoring: !interactive,
      child: MessageCopyButton(key: ValueKey('message-copy-$id'), text: text),
    );
    final row = Transform.translate(
      offset: Offset(user ? _iconInset : -_iconInset, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: user ? [time, const SizedBox(width: 2), copy] : [copy, const SizedBox(width: 2), time],
      ),
    );
    final aligned = Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: row);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animateIn && !reduceMotion ? 0 : 1, end: 1),
      duration: reduceMotion ? Duration.zero : AppMotion.chatReply,
      curve: AppMotion.easeOut,
      builder: (context, progress, child) => Opacity(opacity: progress, child: child),
      child: aligned,
    );
  }
}

class MessageCopyButton extends StatefulWidget {
  const MessageCopyButton({super.key, required this.text});

  final String text;

  @override
  State<MessageCopyButton> createState() => _MessageCopyButtonState();
}

class _MessageCopyButtonState extends State<MessageCopyButton> {
  bool _copied = false;
  bool _pressed = false;
  Timer? _reset;

  Future<void> _copy() async {
    Haptics.tap();
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(AppMotion.copyConfirm, () {
      if (mounted) setState(() => _copied = false);
    });
    await Clipboard.setData(ClipboardData(text: widget.text));
  }

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: _copied ? 'Copied' : 'Copy message',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.text.isEmpty ? null : _copy,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.52 : 1,
          duration: reduceMotion ? Duration.zero : AppMotion.fast,
          child: SizedBox.square(
            dimension: MessageMetaRow.copySize,
            child: Center(
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : AppMotion.chatActionSwap,
                switchInCurve: AppMotion.easeOut,
                switchOutCurve: AppMotion.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: Tween<double>(begin: 0.8, end: 1).animate(animation), child: child),
                ),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                  key: ValueKey(_copied),
                  size: MessageMetaRow.copyIconSize,
                  color: _copied ? skin.textSecondary : skin.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
