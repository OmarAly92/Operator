import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/logic/ansi.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart';

String printable(dynamic payload) {
  if (payload == null) return '';
  if (payload is String) return payload;
  try {
    return const JsonEncoder.withIndent('  ').convert(payload);
  } on JsonUnsupportedObjectError {
    return payload.toString();
  }
}

class ActivityRowWidget extends StatelessWidget {
  const ActivityRowWidget({super.key, required this.activity});

  final ConversationActivityModel activity;

  @override
  Widget build(BuildContext context) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        return _McpToolRow(activity: activity);
      case 'auto_review':
        return _AutoReviewRow(activity: activity);
      case 'file_change':
        return FileChangeActivity(activity: activity);
      case 'plan':
        return PlanCard(activity: activity);
      default:
        return _GenericActivityRow(activity: activity);
    }
  }
}

class _GenericActivityRow extends StatefulWidget {
  const _GenericActivityRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_GenericActivityRow> createState() => _GenericActivityRowState();
}

class _GenericActivityRowState extends State<_GenericActivityRow> {
  bool? _override;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final activity = widget.activity;
    final detail = activity.detail;
    final output = commandOutputText(
      detail?.output ?? detail?.result ?? detail?.error ?? detail?.patchOutput,
    );
    final open = _override ?? activityStartsExpanded(activity);
    final expandable =
        output.isNotEmpty ||
        detail?.cwd != null ||
        detail?.arguments != null ||
        detail?.files != null ||
        detail?.reason != null ||
        detail?.text != null ||
        detail?.terminalInput != null;
    final meta = activityMeta(activity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _override = !open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(meta.icon, size: 13, color: meta.color(skin)),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      '${meta.prefix == null ? '' : '${meta.prefix} '}'
                      '${detail?.command ?? detail?.toolName ?? activity.summary ?? ''}',
                      style: AppTextStyle.mono12Regular.copyWith(
                        color: activity.status == 'failed'
                            ? skin.red
                            : skin.textSecondary,
                      ),
                      maxLines: open ? 6 : 2,
                    ),
                  ),
                  if (activity.status == 'running')
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: skin.orange,
                      ),
                    )
                  else if (activity.status == 'cancelled')
                    AppText(
                      'stopped',
                      style: AppTextStyle.style10Regular.copyWith(
                        color: skin.textFaint,
                      ),
                    ),
                  if (expandable)
                    Icon(
                      open ? Icons.expand_less : Icons.chevron_right,
                      size: 15,
                      color: skin.textFaint,
                    ),
                ],
              ),
            ),
          ),
          if (open) _activityDetails(context, detail, output),
        ],
      ),
    );
  }

  Widget _activityDetails(
    BuildContext context,
    ActivityDetailModel? detail,
    String output,
  ) => Padding(
    padding: const EdgeInsets.only(left: 21, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail?.cwd != null) LabelValue(label: 'cwd', value: detail!.cwd!),
        if (detail?.reason != null || detail?.text != null)
          AppText(
            detail!.reason ?? detail.text!,
            style: AppTextStyle.style12Regular.copyWith(
              color: context.skin.textSecondary,
            ),
            maxLines: 12,
          ),
        if (detail?.arguments != null)
          CodeOutput(value: printable(detail!.arguments)),
        if (detail?.terminalInput != null) ...[
          const VerticalSpace(6),
          const DetailLabel(label: 'agent typed'),
          CodeOutput(value: caretNotation(detail!.terminalInput!)),
          if (detail.terminalInputTruncated == true)
            const PartialNote(
              text:
                  'Operator stopped recording keystrokes at its cap; more were sent.',
            ),
        ],
        if (output.isNotEmpty) CodeOutput(value: output),
        if (detail?.outputTruncated == true ||
            detail?.patchOutputTruncated == true)
          const PartialNote(
            warning: true,
            text:
                'This output is longer than Operator stores, so it stops early. '
                'Open the worktree shell for the full run.',
          )
        else if (detail?.outputMayBePartial == true)
          PartialNote(
            text:
                '${detail!.outputSource == 'stream' ? 'Streamed live; the provider may have omitted the beginning.' : "The provider's rolled-up output may omit the beginning."}'
                ' Open the worktree shell for the full run.',
          ),
        if (detail?.files is List)
          FileNameList(files: detail!.files as List<dynamic>),
      ],
    ),
  );
}

class _McpToolRow extends StatefulWidget {
  const _McpToolRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_McpToolRow> createState() => _McpToolRowState();
}

class _McpToolRowState extends State<_McpToolRow> {
  late bool _open = widget.activity.status == 'failed';

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final failed =
        widget.activity.status == 'failed' ||
        detail?.success == false ||
        detail?.error != null;
    final body =
        detail?.arguments != null ||
        detail?.result != null ||
        detail?.error != null ||
        detail?.progress != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 13,
                    color: failed ? skin.red : skin.purple,
                  ),
                  const HorizontalSpace(8),
                  if (detail?.server != null || detail?.namespace != null)
                    AppText(
                      '${detail!.server ?? detail.namespace}/',
                      style: AppTextStyle.mono11Regular.copyWith(
                        color: skin.purple,
                      ),
                    ),
                  Expanded(
                    child: AppText(
                      detail?.toolName ?? widget.activity.summary ?? '',
                      style: AppTextStyle.mono12Regular.copyWith(
                        color: failed ? skin.red : skin.textSecondary,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  if (detail?.progress != null) ...[
                    const HorizontalSpace(8),
                    Flexible(
                      child: AppText(
                        _lastLine(detail!.progress!),
                        style: AppTextStyle.style10Regular.copyWith(
                          color: skin.textFaint,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                  if (widget.activity.status == 'running')
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: skin.purple,
                      ),
                    )
                  else if (widget.activity.status == 'cancelled')
                    AppText(
                      'stopped',
                      style: AppTextStyle.style10Regular.copyWith(
                        color: skin.textFaint,
                      ),
                    )
                  else if (body)
                    Icon(
                      _open ? Icons.expand_less : Icons.chevron_right,
                      size: 15,
                      color: skin.textFaint,
                    ),
                ],
              ),
            ),
          ),
          if (_open && body)
            Padding(
              padding: const EdgeInsets.only(left: 21, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (detail?.error != null)
                    AppText(
                      detail!.error!,
                      style: AppTextStyle.style12Regular.copyWith(
                        color: skin.red,
                      ),
                      maxLines: 6,
                    ),
                  if (detail?.arguments != null) ...[
                    const DetailLabel(label: 'arguments'),
                    _JsonPayload(payload: detail!.arguments),
                  ],
                  if (detail?.result != null) ...[
                    const DetailLabel(label: 'result'),
                    _JsonPayload(payload: detail!.result),
                  ],
                  if (detail?.progress != null) ...[
                    const DetailLabel(label: 'progress'),
                    CodeOutput(value: detail!.progress!),
                    if (detail.progressTruncated == true)
                      const PartialNote(
                        text: 'Progress was longer than Operator stores.',
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _JsonPayload extends StatelessWidget {
  const _JsonPayload({required this.payload});

  final dynamic payload;

  @override
  Widget build(BuildContext context) {
    final note = _truncationNote(payload);
    if (note == null) return CodeOutput(value: printable(payload));
    return AppText(
      note,
      style: AppTextStyle.style12Regular.copyWith(
        color: context.skin.textSecondary,
      ),
      maxLines: 4,
    );
  }
}

String? _truncationNote(dynamic payload) {
  if (payload is! Map || payload['truncated'] != true) return null;
  final bytes = payload['bytes'];
  final size = bytes is num ? ' (${_formatBytes(bytes)})' : '';
  return 'This payload$size was larger than Operator stores, so it was not kept.';
}

String _formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _lastLine(String progress) {
  return progress.trimRight().split('\n').last;
}

class _AutoReviewRow extends StatefulWidget {
  const _AutoReviewRow({required this.activity});

  final ConversationActivityModel activity;

  @override
  State<_AutoReviewRow> createState() => _AutoReviewRowState();
}

class _AutoReviewRowState extends State<_AutoReviewRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = widget.activity.detail;
    final denied = (detail?.status ?? '').toLowerCase().contains('den');
    final paths = _reviewPaths(detail?.files);
    final body =
        detail?.rationale != null ||
        detail?.command != null ||
        detail?.cwd != null ||
        detail?.host != null ||
        detail?.decisionSource != null ||
        paths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: body ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    denied
                        ? Icons.gpp_bad_outlined
                        : Icons.verified_user_outlined,
                    size: 13,
                    color: denied ? skin.red : skin.green,
                  ),
                  const HorizontalSpace(8),
                  AppText(
                    denied ? 'Auto-declined' : 'Auto-approved',
                    style: AppTextStyle.style11SemiBold.copyWith(
                      color: denied ? skin.red : skin.green,
                    ),
                  ),
                  const HorizontalSpace(8),
                  Expanded(
                    child: AppText(
                      widget.activity.summary ?? '',
                      style: AppTextStyle.mono12Regular.copyWith(
                        color: skin.textSecondary,
                      ),
                    ),
                  ),
                  if (detail?.riskLevel != null)
                    AppText(
                      detail!.riskLevel!,
                      style: AppTextStyle.style10Regular.copyWith(
                        color:
                            [
                              'high',
                              'critical',
                            ].contains(detail.riskLevel!.toLowerCase())
                            ? skin.red
                            : skin.textFaint,
                      ),
                    ),
                  if (body)
                    Icon(
                      _open ? Icons.expand_less : Icons.chevron_right,
                      size: 15,
                      color: skin.textFaint,
                    ),
                ],
              ),
            ),
          ),
          if (_open && body) _reviewDetails(context, denied, paths),
        ],
      ),
    );
  }

  Widget _reviewDetails(BuildContext context, bool denied, List<String> paths) {
    final detail = widget.activity.detail;
    return Padding(
      padding: const EdgeInsets.only(left: 21, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            denied
                ? 'The provider declined this on your behalf. You were not asked.'
                : 'The provider allowed this on your behalf. You were not asked.',
            style: AppTextStyle.style12Regular.copyWith(
              color: context.skin.textSecondary,
            ),
            maxLines: 3,
          ),
          if (detail?.rationale != null)
            AppText(
              detail!.rationale!,
              style: AppTextStyle.style12Regular.copyWith(
                color: context.skin.textTertiary,
              ),
              maxLines: 6,
            ),
          if (detail?.command != null)
            LabelValue(label: 'cmd', value: detail!.command!),
          if (detail?.cwd != null)
            LabelValue(label: 'cwd', value: detail!.cwd!),
          if (detail?.host != null)
            LabelValue(label: 'host', value: detail!.host!),
          if (paths.isNotEmpty)
            LabelValue(label: 'files', value: paths.join(', ')),
          if (detail?.decisionSource != null)
            LabelValue(label: 'by', value: detail!.decisionSource!),
        ],
      ),
    );
  }

  List<String> _reviewPaths(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(
          (entry) => entry is String
              ? entry
              : entry is Map && entry['path'] is String
              ? entry['path'] as String
              : null,
        )
        .whereType<String>()
        .toList();
  }
}
