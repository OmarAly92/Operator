import 'package:equatable/equatable.dart';

class BlockRedactedSpanModel extends Equatable {
  final int? start;
  final int? end;

  const BlockRedactedSpanModel({this.start, this.end});

  factory BlockRedactedSpanModel.fromJson(Map<String, dynamic> json) => BlockRedactedSpanModel(
    start: (json['start'] as num?)?.toInt(),
    end: (json['end'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [start, end];
}

class BlockEventModel extends Equatable {
  final int? seq;
  final String? sessionId;
  final String? sourceId;
  final String? kind;
  final String? source;
  final String? rawEvent;
  final String? harness;
  final String? toolName;
  final String? toolUseId;
  final String? text;
  final String? toolInput;
  final List<BlockRedactedSpanModel>? redactedSpans;
  final String? errorType;
  final String? hookVersion;
  final int? truncatedLines;
  final String? createdAt;
  final String? interactionId;

  const BlockEventModel({
    this.seq,
    this.sessionId,
    this.sourceId,
    this.kind,
    this.source,
    this.rawEvent,
    this.harness,
    this.toolName,
    this.toolUseId,
    this.text,
    this.toolInput,
    this.redactedSpans,
    this.errorType,
    this.hookVersion,
    this.truncatedLines,
    this.createdAt,
    this.interactionId,
  });

  factory BlockEventModel.fromJson(Map<String, dynamic> json) {
    final spans = json['redactedSpans'] as List<dynamic>?;
    return BlockEventModel(
      seq: (json['seq'] as num?)?.toInt(),
      sessionId: json['sessionId'] as String?,
      sourceId: json['sourceId'] as String?,
      kind: json['kind'] as String?,
      source: json['source'] as String?,
      rawEvent: json['rawEvent'] as String?,
      harness: json['harness'] as String?,
      toolName: json['toolName'] as String?,
      toolUseId: json['toolUseId'] as String?,
      text: json['text'] as String?,
      toolInput: json['toolInput'] as String?,
      redactedSpans: spans
          ?.map((span) => BlockRedactedSpanModel.fromJson(span as Map<String, dynamic>))
          .toList(),
      errorType: json['errorType'] as String?,
      hookVersion: json['hookVersion'] as String?,
      truncatedLines: (json['truncatedLines'] as num?)?.toInt(),
      createdAt: json['createdAt'] as String?,
      interactionId: json['interactionId'] as String?,
    );
  }

  static List<BlockEventModel> listFromJson(Map<String, dynamic> json) =>
      (json['blocks'] as List<dynamic>? ?? [])
          .map((block) => BlockEventModel.fromJson(block as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [
    seq,
    sessionId,
    sourceId,
    kind,
    source,
    rawEvent,
    harness,
    toolName,
    toolUseId,
    text,
    toolInput,
    redactedSpans,
    errorType,
    hookVersion,
    truncatedLines,
    createdAt,
    interactionId,
  ];
}
