import 'dart:convert';

import 'package:equatable/equatable.dart';

enum BlockKind { prompt, assistant, reasoning, tool, todo, compaction, permission, notice }

enum BlockStatus { running, ok, failed, blocked }

enum BlockCompactionTrigger { auto, manual }

sealed class BlockDetail extends Equatable {
  const BlockDetail();

  factory BlockDetail.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type == 'unknown') return UnknownBlockDetail(raw: json['raw']);
    if (type == 'shell' &&
        _hasValidFields(json, const {'command': _isString, 'output': _isString, 'exitCode': _isNumber})) {
      return ShellBlockDetail(
        command: json['command'] as String?,
        output: json['output'] as String?,
        exitCode: (json['exitCode'] as num?)?.toInt(),
      );
    }
    if (type == 'file_change' && _hasValidFields(json, const {'files': _isFileChanges, 'truncated': _isBool})) {
      return FileChangeBlockDetail(
        files: (json['files'] as List<dynamic>?)
            ?.map((item) => BlockFileChange.fromJson(item as Map<String, dynamic>))
            .toList(),
        truncated: json['truncated'] as bool?,
      );
    }
    if (type == 'plan' && _hasValidFields(json, const {'steps': _isPlanSteps})) {
      return PlanBlockDetail(
        steps: (json['steps'] as List<dynamic>?)
            ?.map((item) => BlockPlanStep.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    }
    if (type == 'mcp_tool' &&
        _hasValidFields(json, const {'server': _isString, 'tool': _isString, 'result': _isString})) {
      return McpToolBlockDetail(
        server: json['server'] as String?,
        tool: json['tool'] as String?,
        args: json['args'],
        result: json['result'] as String?,
      );
    }
    if (type == 'usage' &&
        _hasValidFields(json, const {
          'contextUsed': _isNumber,
          'contextWindow': _isNumber,
          'inputTokens': _isNumber,
          'outputTokens': _isNumber,
        })) {
      return UsageBlockDetail(
        contextUsed: (json['contextUsed'] as num?)?.toInt(),
        contextWindow: (json['contextWindow'] as num?)?.toInt(),
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
      );
    }
    if (type == 'compaction' &&
        _hasValidFields(json, const {'trigger': _isCompactionTrigger, 'preTokens': _isNumber})) {
      return CompactionBlockDetail(
        trigger: json['trigger'] == null
            ? null
            : json['trigger'] == 'auto'
            ? BlockCompactionTrigger.auto
            : BlockCompactionTrigger.manual,
        preTokens: (json['preTokens'] as num?)?.toInt(),
      );
    }
    return UnknownBlockDetail(raw: json);
  }
}

typedef _DetailValidator = bool Function(Object? value);

bool _hasValidFields(Map<String, dynamic> json, Map<String, _DetailValidator> validators) =>
    validators.entries.every((entry) => !json.containsKey(entry.key) || entry.value(json[entry.key]));

bool _isString(Object? value) => value == null || value is String;

bool _isNumber(Object? value) => value == null || value is num;

bool _isBool(Object? value) => value == null || value is bool;

bool _isCompactionTrigger(Object? value) => value == null || value == 'auto' || value == 'manual';

bool _isFileChanges(Object? value) =>
    value == null ||
    value is List &&
        value.every(
          (item) =>
              item is Map<String, dynamic> &&
              _hasValidFields(item, const {
                'path': _isString,
                'oldPath': _isString,
                'status': _isString,
                'additions': _isNumber,
                'deletions': _isNumber,
              }),
        );

bool _isPlanSteps(Object? value) =>
    value == null ||
    value is List &&
        value.every(
          (item) =>
              item is Map<String, dynamic> && _hasValidFields(item, const {'text': _isString, 'status': _isString}),
        );

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
  const BlockFileChange({this.path, this.oldPath, this.status, this.additions, this.deletions});

  factory BlockFileChange.fromJson(Map<String, dynamic> json) => BlockFileChange(
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

  factory BlockPlanStep.fromJson(Map<String, dynamic> json) =>
      BlockPlanStep(text: json['text'] as String?, status: json['status'] as String?);

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
  const UsageBlockDetail({this.contextUsed, this.contextWindow, this.inputTokens, this.outputTokens});

  final int? contextUsed;
  final int? contextWindow;
  final int? inputTokens;
  final int? outputTokens;

  @override
  List<Object?> get props => [contextUsed, contextWindow, inputTokens, outputTokens];
}

class CompactionBlockDetail extends BlockDetail {
  const CompactionBlockDetail({this.trigger, this.preTokens});

  final BlockCompactionTrigger? trigger;
  final int? preTokens;

  @override
  List<Object?> get props => [trigger, preTokens];
}

class QuestionBlockDetail extends BlockDetail {
  const QuestionBlockDetail({required this.questions});

  final List<BlockQuestion> questions;

  @override
  List<Object?> get props => [questions];
}

class BlockQuestion extends Equatable {
  const BlockQuestion({this.question, this.header, this.multiSelect, this.options = const []});

  final String? question;
  final String? header;
  final bool? multiSelect;
  final List<BlockQuestionOption> options;

  @override
  List<Object?> get props => [question, header, multiSelect, options];
}

class BlockQuestionOption extends Equatable {
  const BlockQuestionOption({this.label, this.description});

  final String? label;
  final String? description;

  @override
  List<Object?> get props => [label, description];
}

class UnknownBlockDetail extends BlockDetail {
  const UnknownBlockDetail({this.raw});

  final Object? raw;

  @override
  List<Object?> get props => [raw];
}

class BlockDisplay extends Equatable {
  const BlockDisplay({required this.displayName, required this.summary, this.errorText});

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
    this.result,
    this.model,
    this.errorType,
    this.truncatedLines = 0,
    this.redacted = false,
    this.createdAt,
    this.children,
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
  final String? result;
  final String? model;
  final String? errorType;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;
  final List<SessionBlock>? children;

  SessionBlock copyWith({
    BlockKind? kind,
    BlockStatus? status,
    String? turnId,
    String? title,
    String? body,
    String? result,
    String? model,
    BlockDetail? detail,
    int? lastSeq,
    String? errorType,
    int? truncatedLines,
    bool? redacted,
    String? createdAt,
    List<SessionBlock>? children,
  }) => SessionBlock(
    id: id,
    firstSeq: firstSeq,
    lastSeq: lastSeq ?? this.lastSeq,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    turnId: turnId ?? this.turnId,
    title: title ?? this.title,
    body: body ?? this.body,
    result: result ?? this.result,
    model: model ?? this.model,
    detail: detail ?? this.detail,
    toolName: toolName,
    errorType: errorType ?? this.errorType,
    truncatedLines: truncatedLines ?? this.truncatedLines,
    redacted: redacted ?? this.redacted,
    createdAt: createdAt ?? this.createdAt,
    children: children ?? this.children,
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
    result,
    model,
    errorType,
    truncatedLines,
    redacted,
    createdAt,
    children,
  ];
}

BlockDisplay blockDisplay(SessionBlock block) {
  final detail = block.detail;
  if (detail == null) {
    return BlockDisplay(displayName: block.title, summary: block.body);
  }

  return switch (detail) {
    ShellBlockDetail(:final command, :final output, :final exitCode) => BlockDisplay(
      displayName: 'Shell',
      summary: [command, output].whereType<String>().where((part) => part.isNotEmpty).join('\n\n'),
      errorText: exitCode == null || exitCode == 0 ? null : 'Exit code $exitCode',
    ),
    FileChangeBlockDetail(:final files) => BlockDisplay(
      displayName: 'File change',
      summary: '${files?.length ?? 0} ${(files?.length ?? 0) == 1 ? 'file' : 'files'} changed',
    ),
    PlanBlockDetail(:final steps) => BlockDisplay(
      displayName: 'Plan',
      summary: '${steps?.length ?? 0} ${(steps?.length ?? 0) == 1 ? 'step' : 'steps'}',
    ),
    McpToolBlockDetail(:final server, :final tool, :final result) => BlockDisplay(
      displayName: '${server ?? ''}/${tool ?? ''}',
      summary: result ?? '',
    ),
    UsageBlockDetail(:final contextUsed, :final contextWindow) => BlockDisplay(
      displayName: 'Usage',
      summary: '${contextUsed ?? ''} / ${contextWindow ?? ''} context',
    ),
    CompactionBlockDetail(:final trigger, :final preTokens) => BlockDisplay(
      displayName: 'Compaction',
      summary: '${trigger?.name ?? ''} at ${preTokens ?? ''} tokens',
    ),
    QuestionBlockDetail() => BlockDisplay(
      displayName: block.title,
      summary: block.body,
    ),
    UnknownBlockDetail(:final raw) => BlockDisplay(
      displayName: block.title,
      summary: block.body.isNotEmpty
          ? block.body
          : raw is String
          ? raw
          : jsonEncode(raw),
    ),
  };
}
