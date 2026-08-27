import 'package:equatable/equatable.dart';

enum BlockKind { prompt, assistant, tool, permission, notice }

enum BlockStatus { running, ok, failed, blocked }

class SessionBlock extends Equatable {
  const SessionBlock({
    required this.id,
    required this.firstSeq,
    required this.lastSeq,
    required this.kind,
    required this.status,
    required this.title,
    required this.body,
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
  final String title;
  final String body;
  final String? toolName;
  final String? errorType;
  final int truncatedLines;
  final bool redacted;
  final String? createdAt;

  SessionBlock copyWith({
    BlockStatus? status,
    String? body,
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
    title: title,
    body: body ?? this.body,
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
    title,
    body,
    toolName,
    errorType,
    truncatedLines,
    redacted,
    createdAt,
  ];
}
