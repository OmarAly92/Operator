import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

class ChatActionButton extends StatelessWidget {
  const ChatActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.primary = false,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final VoidCallback onPressed;
  final bool primary;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final fill = danger
        ? skin.tintRed
        : (primary ? skin.blue : skin.bgElevated);
    final ink = danger
        ? skin.red
        : (primary ? skin.onAccent : skin.textPrimary);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled
              ? () {
                  Haptics.tap();
                  onPressed();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  label,
                  style: AppTextStyle.style13SemiBold.copyWith(color: ink),
                ),
                if (hint != null) ...[
                  const VerticalSpace(2),
                  AppText(
                    hint!,
                    style: AppTextStyle.style10Regular.copyWith(
                      color: skin.textTertiary,
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DetailLabel extends StatelessWidget {
  const DetailLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => AppText(
    label.toUpperCase(),
    style: AppTextStyle.mono10Regular.copyWith(
      color: context.skin.textFaint,
      letterSpacing: 0.7,
    ),
  );
}

class LabelValue extends StatelessWidget {
  const LabelValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailLabel(label: label),
        const HorizontalSpace(8),
        Expanded(
          child: SelectableText(
            value,
            style: AppTextStyle.mono11Regular.copyWith(
              color: context.skin.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class CodeOutput extends StatelessWidget {
  const CodeOutput({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: value));
        Haptics.success();
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: skin.bgColumn,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          value,
          style: AppTextStyle.mono11Regular.copyWith(
            color: skin.textSecondary,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class PartialNote extends StatelessWidget {
  const PartialNote({super.key, required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppText(
        text,
        style: AppTextStyle.style10Regular.copyWith(
          color: warning ? skin.amber : skin.textTertiary,
        ),
        maxLines: 4,
      ),
    );
  }
}
