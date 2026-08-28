import 'dart:convert';

import 'package:equatable/equatable.dart';

enum BlockKind {
  prompt,
  assistant,
  reasoning,
  tool,
  todo,
  compaction,
  permission,
  notice,
}

enum BlockStatus { running, ok, failed, blocked }

enum BlockCompactionTrigger { auto, manual }

sealed class BlockDetail extends Equatable {
  const BlockDetail();

  factory BlockDetail.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'shell' => ShellBlockDetail(
          command: json['command'] as String?,
          output: json['output'] as String?,
          exitCode: (json['exitCode'] as num?)?.toInt(),
        ),
        'file_change' => FileChangeBlockDetail(
          files: (json['files'] as List<dynamic>?)
              ?.map(
                (item) =>
                    BlockFileChange.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
          truncated: json['truncated'] as bool?,
        ),
        'plan' => PlanBlockDetail(
          steps: (json['steps'] as List<dynamic>?)
              ?.map(
                (item) => BlockPlanStep.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
        ),
        'mcp_tool' => McpToolBlockDetail(
          server: json['server'] as String?,
          tool: json['tool'] as String?,
          args: json['args'],
          result: json['result'] as String?,
        ),
        'usage' => UsageBlockDetail(
          contextUsed: (json['contextUsed'] as num?)?.toInt(),
          contextWindow: (json['contextWindow'] as num?)?.toInt(),
          inputTokens: (json['inputTokens'] as num?)?.toInt(),
          outputTokens: (json['outputTokens'] as num?)?.toInt(),
        ),
    'compaction' => CompactionBlockDetail(
      trigger: switch (json['trigger']) {
        'manual' => BlockCompactionTrigger.manual,
        _ => BlockCompactionTrigger.auto,
      },
          preTokens: (json['preTokens'] as num?)?.toInt(),
        ),
        _ => UnknownBlockDetail(raw: json['raw']),
      };
}

class ShellBlockDetail extends BlockDetail {
  const ShellBlockDetail({this.command, this.output, this.exitCode});

  final String? command;
  final String? output;
  final int? exitCode;

  @override
  List<Object?> get props => [command, output, exitCode];
}

class FileChangeBlockDetail extends BlockDetail {
  const FileChangeBlockDetail({this.files, this.truncated});

  final List<BlockFileChange>? files;
  final bool? truncated;

  @override
  List<Object?> get props => [files, truncated];
}

class BlockFileChange extends Equatable {
  const BlockFileChange({
    this.path,
    this.oldPath,
    this.status,
    this.additions,
    this.deletions,
  });

  factory BlockFileChange.fromJson(Map<String, dynamic> json) =>
      BlockFileChange(
        path: json['path'] as String?,
        oldPath: json['oldPath'] as String?,
        status: json['status'] as String?,
        additions: (json['additions'] as num?)?.toInt(),
        deletions: (json['deletions'] as num?)?.toInt(),
      );

  final String? path;
  final String? oldPath;
  final String? status;
  final int? additions;
  final int? deletions;

  @override
  List<Object?> get props => [path, oldPath, status, additions, deletions];
}

class PlanBlockDetail extends BlockDetail {
  const PlanBlockDetail({this.steps});

  final List<BlockPlanStep>? steps;

  @override
  List<Object?> get props => [steps];
}

class BlockPlanStep extends Equatable {
  const BlockPlanStep({this.text, this.status});

  factory BlockPlanStep.fromJson(Map<String, dynamic> json) => BlockPlanStep(
    text: json['text'] as String?,
    status: json['status'] as String?,
  );

  final String? text;
  final String? status;

  @override
  List<Object?> get props => [text, status];
}

class McpToolBlockDetail extends BlockDetail {
  const McpToolBlockDetail({this.server, this.tool, this.args, this.result});

  final String? server;
  final String? tool;
  final Object? args;
  final String? result;

  @override
  List<Object?> get props => [server, tool, args, result];
}

class UsageBlockDetail extends BlockDetail {
  const UsageBlockDetail({
    this.contextUsed,
    this.contextWindow,
    this.inputTokens,
    this.outputTokens,
  });

  final int? contextUsed;
  final int? contextWindow;
  final int? inputTokens;
  final int? outputTokens;

  @override
  List<Object?> get props => [
    contextUsed,
    contextWindow,
    inputTokens,
    outputTokens,
  ];
}

class CompactionBlockDetail extends BlockDetail {
  const CompactionBlockDetail({this.trigger, this.preTokens});

  final BlockCompactionTrigger? trigger;
  final int? preTokens;

  @override
  List<Object?> get props => [trigger, preTokens];
}

class UnknownBlockDetail extends BlockDetail {
  const UnknownBlockDetail({this.raw});

  final Object? raw;

  @override
  List<Object?> get props => [raw];
}

class BlockDisplay extends Equatable {
  const BlockDisplay({
    required this.displayName,
    required this.summary,
    this.errorText,
  });

  final String displayName;
  final String summary;
  final String? errorText;

  @override
  List<Object?> get props => [displayName, summary, errorText];
}

class SessionBlock extends Equatable {
  const SessionBlock({
    required this.id,
    required this.firstSeq,
    required this.lastSeq,
    required this.kind,
    required this.status,
    this.turnId,
    required this.title,
    required this.body,
    this.detail,
    this.toolName,
    this.errorType,
    this.truncatedLines = 0,
    this.redacted = false,
    this.createdAt,
  });

  final String id;
  final int firstSeq;
  final int lastSeq;
  final BlockKind kind;
  final BlockStatus status;
  final String? turnId;
  final String title;
  final String body;
  final BlockDetail? detail;
  final String? toolName;
  final String? errorType;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;

  SessionBlock copyWith({
    BlockStatus? status,
    String? turnId,
    String? body,
    BlockDetail? detail,
    int? lastSeq,
    String? errorType,
    int? truncatedLines,
    bool? redacted,
    String? createdAt,
  }) => SessionBlock(
    id: id,
    firstSeq: firstSeq,
    lastSeq: lastSeq ?? this.lastSeq,
    kind: kind,
    status: status ?? this.status,
    turnId: turnId ?? this.turnId,
    title: title,
    body: body ?? this.body,
    detail: detail ?? this.detail,
    toolName: toolName,
    errorType: errorType ?? this.errorType,
    truncatedLines: truncatedLines ?? this.truncatedLines,
    redacted: redacted ?? this.redacted,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    firstSeq,
    lastSeq,
    kind,
    status,
    turnId,
    title,
    body,
    detail,
    toolName,
    errorType,
    truncatedLines,
    redacted,
    createdAt,
  ];
}

BlockDisplay blockDisplay(SessionBlock block) {
  final detail = block.detail;
  if (detail == null) {
    return BlockDisplay(displayName: block.title, summary: block.body);
  }

  return switch (detail) {
    ShellBlockDetail(:final command, :final output, :final exitCode) =>
      BlockDisplay(
        displayName: 'Shell',
        summary: [
          command,
          output,
        ].whereType<String>().where((part) => part.isNotEmpty).join('\n\n'),
        errorText: exitCode == null || exitCode == 0
            ? null
            : 'Exit code $exitCode',
      ),
    FileChangeBlockDetail(:final files) => BlockDisplay(
      displayName: 'File change',
      summary:
          '${files?.length ?? 0} ${(files?.length ?? 0) == 1 ? 'file' : 'files'} changed',
    ),
    PlanBlockDetail(:final steps) => BlockDisplay(
      displayName: 'Plan',
      summary:
          '${steps?.length ?? 0} ${(steps?.length ?? 0) == 1 ? 'step' : 'steps'}',
    ),
    McpToolBlockDetail(:final server, :final tool, :final result) =>
      BlockDisplay(
        displayName: '${server ?? ''}/${tool ?? ''}',
        summary: result ?? '',
      ),
    UsageBlockDetail(:final contextUsed, :final contextWindow) => BlockDisplay(
      displayName: 'Usage',
      summary: '${contextUsed ?? 0} / ${contextWindow ?? 0} context',
    ),
    CompactionBlockDetail(:final trigger, :final preTokens) => BlockDisplay(
      displayName: 'Compaction',
      summary: '${trigger?.name ?? 'auto'} at ${preTokens ?? 0} tokens',
    ),
    UnknownBlockDetail(:final raw) => BlockDisplay(
      displayName: block.title,
      summary: block.body.isEmpty ? jsonEncode(raw) : block.body,
    ),
  };
}
