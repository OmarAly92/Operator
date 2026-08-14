import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:url_launcher/url_launcher.dart';

class UserInputCard extends StatefulWidget {
  const UserInputCard({
    super.key,
    required this.activity,
    required this.busy,
    required this.onResolve,
  });

  final ConversationActivityModel activity;
  final bool busy;
  final Future<void> Function(
    String requestId,
    String action, [
    Map<String, dynamic>? content,
  ])
  onResolve;

  @override
  State<UserInputCard> createState() => _UserInputCardState();
}

class _UserInputCardState extends State<UserInputCard> {
  late Map<String, dynamic> _values = {
    for (final entry
        in (widget.activity.detail?.schema?.properties ?? const {}).entries)
      entry.key: initialInputValue(entry.value),
  };
  String? _validationError;
  String? _submitError;
  bool _submitting = false;

  Future<void> _resolve(String action, [Map<String, dynamic>? content]) async {
    final requestId = widget.activity.requestId;
    if (_submitting || requestId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.onResolve(requestId, action, content);
    } catch (error) {
      if (mounted) setState(() => _submitError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit(InputSchemaModel? schema) async {
    final missing = missingRequiredInputs(schema?.required, _values);
    if (missing.isNotEmpty) {
      final missingName = missing.first;
      final property = schema?.properties[missingName];
      setState(
        () => _validationError =
            'Complete ${property?.title ?? humanizeInputName(missingName)} before continuing.',
      );
      return;
    }
    for (final entry in (schema?.properties ?? const {}).entries) {
      final problem = validateInput(entry.value, _values[entry.key]);
      if (problem != null) {
        setState(
          () => _validationError =
              '${entry.value.title ?? humanizeInputName(entry.key)} $problem.',
        );
        return;
      }
    }
    setState(() => _validationError = null);
    await _resolve('accept', _values);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final schema = detail?.schema;
    final pending = activity.isPending;
    final isUrlMode = detail?.inputMode == 'url';
    final url = isUrlMode ? safeHttpUrl(detail?.url) : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border.all(color: pending ? skin.blue : skin.borderDefault),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 15,
                color: pending ? skin.blue : skin.textTertiary,
              ),
              const HorizontalSpace(8),
              Expanded(
                child: AppText(
                  schema?.title ??
                      (pending ? 'Agent needs input' : 'Input resolved'),
                  style: AppTextStyle.style13SemiBold,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const VerticalSpace(7),
          AppText(
            detail?.message ?? schema?.description ?? activity.summary ?? '',
            style: AppTextStyle.style12Regular.copyWith(
              color: skin.textSecondary,
            ),
            maxLines: 8,
          ),
          if (pending && isUrlMode) ...[
            const VerticalSpace(9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: skin.bgColumn,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url?.toString() ??
                    'The provider supplied an unsafe or invalid URL.',
                style: AppTextStyle.mono11Regular.copyWith(
                  color: skin.textSecondary,
                ),
              ),
            ),
          ],
          if (pending && !isUrlMode && schema != null)
            for (final entry in schema.properties.entries)
              _InputField(
                name: entry.key,
                property: entry.value,
                required: schema.required.contains(entry.key),
                value: _values[entry.key],
                onChanged: (value) => setState(() {
                  _validationError = null;
                  _values = {..._values, entry.key: value};
                }),
              ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _validationError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(
                _submitError!,
                style: AppTextStyle.style12Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          const VerticalSpace(10),
          if (pending && activity.requestId != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChatActionButton(
                  label: 'Cancel',
                  enabled: !widget.busy && !_submitting,
                  onPressed: () => _resolve('cancel'),
                ),
                ChatActionButton(
                  label: isUrlMode ? 'Decline' : 'Skip',
                  enabled: !widget.busy && !_submitting,
                  onPressed: () => _resolve('decline'),
                ),
                if (isUrlMode)
                  ChatActionButton(
                    label: _submitting ? 'Opening…' : 'Open link',
                    primary: true,
                    enabled: !widget.busy && !_submitting && url != null,
                    onPressed: () async {
                      if (url == null) return;
                      final opened = await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!mounted) return;
                      if (opened) {
                        await _resolve('accept');
                      } else {
                        setState(
                          () => _validationError =
                              'This link could not be opened on this device.',
                        );
                      }
                    },
                  )
                else if (!isUrlMode)
                  ChatActionButton(
                    label: _submitting ? 'Sending…' : 'Continue',
                    primary: true,
                    enabled: !widget.busy && !_submitting,
                    onPressed: () => _submit(schema),
                  ),
              ],
            )
          else if (pending)
            const PartialNote(
              warning: true,
              text:
                  'This request has no provider identity, so Operator cannot answer it safely. '
                  'Open diagnostics on the host.',
            )
          else
            const PartialNote(
              text: 'Already answered. This card is kept for the record.',
            ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.name,
    required this.property,
    required this.required,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final InputPropertyModel property;
  final bool required;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final label =
        '${property.title ?? humanizeInputName(name)}${required ? ' *' : ''}';

    if (property.type == 'boolean') {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: AppText(label, style: AppTextStyle.style12SemiBold),
            ),
            Switch(
              value: value == true,
              activeThumbColor: skin.blue,
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    final options = inputOptions(property);
    if (options.isNotEmpty) {
      final multi = property.type == 'array';
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(label, style: AppTextStyle.style12SemiBold),
            if (property.description != null)
              AppText(
                property.description!,
                style: AppTextStyle.style10Regular.copyWith(
                  color: skin.textTertiary,
                ),
                maxLines: 3,
              ),
            const VerticalSpace(6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in options)
                  ChatActionButton(
                    label: choice.label,
                    hint: choice.description,
                    primary: multi
                        ? (value is List &&
                              (value as List).contains(choice.value))
                        : value == choice.value,
                    onPressed: () => onChanged(
                      multi
                          ? toggleInputValue(
                              value is List ? value as List<dynamic> : const [],
                              choice.value,
                            )
                          : choice.value,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final numeric = property.type == 'number' || property.type == 'integer';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(label, style: AppTextStyle.style12SemiBold),
          if (property.description != null)
            AppText(
              property.description!,
              style: AppTextStyle.style10Regular.copyWith(
                color: skin.textTertiary,
              ),
              maxLines: 3,
            ),
          const VerticalSpace(6),
          TextField(
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            maxLength: property.maxLength,
            style: AppTextStyle.style14Regular.copyWith(
              color: skin.textPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: skin.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: skin.borderDefault),
              ),
            ),
            onChanged: (text) => onChanged(
              numeric ? (text.isEmpty ? '' : num.tryParse(text) ?? text) : text,
            ),
          ),
        ],
      ),
    );
  }
}
