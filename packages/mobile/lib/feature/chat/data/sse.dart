import 'dart:convert';

import 'package:equatable/equatable.dart';

final RegExp _boundary = RegExp(r'\r?\n\r?\n');

class SseSplit {
  const SseSplit({required this.frames, required this.remainder});

  final List<String> frames;
  final String remainder;
}

class ConversationEventModel extends Equatable {
  const ConversationEventModel({
    required this.seq,
    this.projectId,
    this.sessionId,
    this.type,
    this.payload,
    this.createdAt,
  });

  final int seq;
  final String? projectId;
  final String? sessionId;
  final String? type;
  final Map<String, dynamic>? payload;
  final String? createdAt;

  bool get touchesConversation => payload?['conversationId'] != null;

  @override
  List<Object?> get props => [seq, projectId, sessionId, type, payload, createdAt];
}

SseSplit takeSseFrames(String buffer) {
  final frames = <String>[];
  var remainder = buffer;
  var boundary = _boundary.firstMatch(remainder);
  while (boundary != null) {
    frames.add(remainder.substring(0, boundary.start));
    remainder = remainder.substring(boundary.end);
    boundary = _boundary.firstMatch(remainder);
  }
  return SseSplit(frames: frames, remainder: remainder);
}

ConversationEventModel? parseSseFrame(String frame) {
  var id = 0;
  final data = <String>[];
  for (final raw in frame.replaceAll('\r', '').split('\n')) {
    if (raw.startsWith('id:')) {
      id = int.tryParse(raw.substring(3).trim()) ?? 0;
    } else if (raw.startsWith('data:')) {
      data.add(raw.substring(5).trimLeft());
    }
  }
  if (data.isEmpty) return null;

  try {
    final decoded = jsonDecode(data.join('\n'));
    if (decoded is! Map<String, dynamic>) return null;
    final seq = decoded['seq'];
    return ConversationEventModel(
      seq: seq is num ? seq.toInt() : id,
      projectId: decoded['projectId'] as String?,
      sessionId: decoded['sessionId'] as String?,
      type: decoded['type'] as String?,
      payload: decoded['payload'] as Map<String, dynamic>?,
      createdAt: decoded['createdAt'] as String?,
    );
  } catch (_) {
    return null;
  }
}
