import 'dart:convert';

import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_question.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

List<SessionBlock> assembleBlocks(Iterable<BlockEventModel> events) {
  final ordered = events.where((event) => event.seq != null).toList()..sort((a, b) => a.seq!.compareTo(b.seq!));

  final blocks = <SessionBlock>[];
  final indexById = <String, int>{};
  final consumed = <int>{};
  final bodyFromTranscript = <String>{};
  final statusFromHook = <String>{};

  String? model;
  int? todoIndex;
  int? questionIndex;
  int? hookQuestionIndex;
  final hookQuestionIds = <String>{};
  final droppedIndexes = <int>{};
  var sawTranscriptAssistant = false;
  int? hookAssistantIndex;
  var lastPromptSeq = 0;

  for (final event in ordered) {
    final seq = event.seq!;
    if (!consumed.add(seq)) continue;

    final key = _correlationKey(event);
    var id = _blockId(event, key);
    final text = event.text ?? '';
    final fromTranscript = event.source == 'transcript';

    switch (event.kind) {
      case 'idle_prompt':
      case 'session_start':
        continue;

      case 'prompt_submit':
        _answerBlocked(blocks, seq);
        lastPromptSeq = seq;
        todoIndex = null;
        questionIndex = null;
        hookQuestionIndex = null;
        sawTranscriptAssistant = false;
        hookAssistantIndex = null;
        _upsert(blocks, indexById, _create(event, id, BlockKind.prompt, BlockStatus.running, 'Prompt', text, model));

      case 'turn_model':
        if (text.isNotEmpty) model = text;

      case 'assistant_text':
        sawTranscriptAssistant = true;
        final title = event.rawEvent == 'commentary' ? 'Assistant · note' : 'Assistant';
        final block = _create(event, id, BlockKind.assistant, BlockStatus.ok, title, text, model);
        final hookAt = hookAssistantIndex;
        if (hookAt != null) {
          indexById.remove(blocks[hookAt].id);
          blocks[hookAt] = block;
          indexById[block.id] = hookAt;
          hookAssistantIndex = null;
        } else {
          _upsert(blocks, indexById, block);
        }

      case 'reasoning':
        _upsert(blocks, indexById, _create(event, id, BlockKind.reasoning, BlockStatus.ok, 'Reasoning', text, model));

      case 'compaction':
        _upsert(blocks, indexById, _create(event, id, BlockKind.compaction, BlockStatus.ok, 'Compaction', text, model));

      case 'todo':
        if (todoIndex != null) {
          blocks[todoIndex] = blocks[todoIndex].copyWith(body: text, lastSeq: seq);
          indexById[id] = todoIndex;
        } else {
          _upsert(blocks, indexById, _create(event, id, BlockKind.todo, BlockStatus.ok, 'Todo', text, model));
          todoIndex = indexById[id];
        }

      case 'tool_start':
        bodyFromTranscript.add(id);
        final at = indexById[id];
        final body = event.toolInput ?? '';
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            body: body,
            lastSeq: seq,
            status: statusFromHook.contains(id) ? null : BlockStatus.running,
            detail: switch (blocks[at].detail) {
              AgentBlockDetail(:final withInput) => withInput(body),
              _ => event.toolName == 'Agent' ? AgentBlockDetail.fromToolInput(body) : null,
            },
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, BlockStatus.running, event.toolName ?? 'Tool', body, model),
          );
        }

      case 'tool_result':
        final failed = (event.errorType ?? '').isNotEmpty;
        final resolved = failed ? BlockStatus.failed : BlockStatus.ok;
        final at = indexById[id];
        if (at != null) {
          final target = blocks[at];
          final answered = target.kind == BlockKind.permission && target.status == BlockStatus.blocked;
          final agentDetail = target.detail is AgentBlockDetail && (event.detail ?? '').isNotEmpty
              ? (target.detail! as AgentBlockDetail).merge(_decodeMap(event.detail!))
              : null;
          blocks[at] = _answered(
            target.copyWith(
              result: target.kind == BlockKind.todo ? null : text,
              lastSeq: seq,
              errorType: event.errorType,
              status: statusFromHook.contains(id) && !answered ? null : resolved,
              detail: agentDetail,
            ),
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, resolved, event.toolName ?? 'Tool', '', model, result: text),
          );
        }

      case 'tool_complete':
        statusFromHook.add(id);
        final failed = (event.errorType ?? '').isNotEmpty;
        final status = failed ? BlockStatus.failed : BlockStatus.ok;
        final hookBody = _join([event.toolInput ?? '', text], '\n\n');
        final at = indexById[id];
        if (at != null) {
          blocks[at] = _answered(
            blocks[at].copyWith(
              status: status,
              body: bodyFromTranscript.contains(id) ? null : hookBody,
              lastSeq: seq,
              errorType: event.errorType,
              truncatedLines: event.truncatedLines ?? 0,
              redacted: _isRedacted(event) || blocks[at].redacted,
            ),
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, status, event.toolName ?? 'Tool', hookBody, model),
          );
        }

      case 'permission_request':
        if (key == null) {
          final adopted = _soleRunningTool(blocks, event.toolName);
          if (adopted != null) id = adopted;
        }
        statusFromHook.add(id);
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            kind: BlockKind.permission,
            title: 'Permission requested',
            status: BlockStatus.blocked,
            lastSeq: seq,
            interactionId: event.interactionId ?? blocks[at].interactionId,
          );
        } else {
          final detail = (event.toolInput ?? '').isNotEmpty ? event.toolInput! : text;
          _upsert(
            blocks,
            indexById,
            _create(
              event,
              id,
              BlockKind.permission,
              BlockStatus.blocked,
              'Permission requested',
              _join([event.toolName ?? '', detail], '\n'),
              model,
            ),
          );
        }
        if (event.toolName == 'AskUserQuestion') {
          hookQuestionIndex = indexById[id];
          hookQuestionIds.add(id);
        }

      case 'question_asked':
        final questions = fromTranscript ? parseQuestionDetail(event.toolInput ?? '') : null;
        if (!fromTranscript && questionIndex != null) continue;
        final title = questions?.questions.first.question ?? 'Waiting on you';
        final body = fromTranscript ? '' : text;
        final block = _create(event, id, BlockKind.notice, BlockStatus.blocked, title, body, model, detail: questions);
        if (fromTranscript && hookQuestionIndex != null) {
          final interactionId = blocks[hookQuestionIndex].interactionId;
          hookQuestionIds.remove(blocks[hookQuestionIndex].id);
          indexById.remove(blocks[hookQuestionIndex].id);
          final toolAt = indexById[block.id];
          if (toolAt != null && toolAt != hookQuestionIndex) droppedIndexes.add(toolAt);
          blocks[hookQuestionIndex] = block.copyWith(interactionId: interactionId);
          indexById[block.id] = hookQuestionIndex;
          questionIndex = hookQuestionIndex;
          hookQuestionIndex = null;
        } else if (fromTranscript && indexById[block.id] != null) {
          final at = indexById[block.id]!;
          blocks[at] = block.copyWith(interactionId: blocks[at].interactionId);
          questionIndex = at;
        } else {
          _upsert(blocks, indexById, block);
          questionIndex = indexById[block.id];
          if (!fromTranscript) {
            hookQuestionIndex = questionIndex;
            hookQuestionIds.add(block.id);
          }
        }

      case 'permission_replied':
        final at = indexById[id];
        if (at != null) {
          blocks[at] = _answered(blocks[at].copyWith(status: BlockStatus.ok, lastSeq: seq));
        }

      case 'stop':
      case 'stop_failure':
        _answerBlocked(blocks, seq);
        questionIndex = null;
        hookQuestionIndex = null;
        final failed = event.kind == 'stop_failure';
        final at = _lastRunningPrompt(blocks);
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: failed ? BlockStatus.failed : BlockStatus.ok, lastSeq: seq);
        }
        if (text.isNotEmpty && !sawTranscriptAssistant) {
          _upsert(
            blocks,
            indexById,
            _create(
              event,
              id,
              BlockKind.assistant,
              failed ? BlockStatus.failed : BlockStatus.ok,
              'Assistant',
              text,
              model,
            ),
          );
          hookAssistantIndex = indexById[id];
        }

      case 'agent_start':
        final started = _decodeMap(event.detail ?? '');
        final at = indexById[id];
        if (at != null) {
          final current = blocks[at].detail;
          final base = current is AgentBlockDetail
              ? current
              : AgentBlockDetail.fromToolInput(blocks[at].body) ?? const AgentBlockDetail(status: 'running');
          blocks[at] = blocks[at].copyWith(detail: base.merge(started), lastSeq: seq);
        } else {
          _upsert(
            blocks,
            indexById,
            _create(
              event,
              id,
              BlockKind.tool,
              BlockStatus.running,
              'Agent',
              '',
              model,
              detail: const AgentBlockDetail(status: 'running').merge(started),
            ),
          );
        }

      case 'agent_stop':
        final stopped = (event.agentId ?? '').isNotEmpty ? event.agentId! : (event.sourceId ?? '');
        if (stopped.isEmpty) continue;
        for (var i = 0; i < blocks.length; i++) {
          final detail = blocks[i].detail;
          if (detail is AgentBlockDetail && detail.agentId == stopped && !detail.finished) {
            blocks[i] = blocks[i].copyWith(detail: detail.merge(const {'status': 'completed'}), lastSeq: seq);
          }
        }

      case 'unknown':
      case 'task_update':
        break;

      default:
        final raw = event.rawEvent ?? '';
        _upsert(
          blocks,
          indexById,
          _create(event, id, BlockKind.notice, BlockStatus.ok, raw.isNotEmpty ? raw : 'Event', text, model),
        );
    }
  }

  return [
    for (var i = 0; i < blocks.length; i++)
      if (!droppedIndexes.contains(i) && !hookQuestionIds.contains(blocks[i].id) && !_isStaleQuestion(blocks[i], lastPromptSeq))
        blocks[i],
  ];
}

bool _isStaleQuestion(SessionBlock block, int lastPromptSeq) =>
    block.kind == BlockKind.notice &&
    block.status == BlockStatus.blocked &&
    block.detail is! QuestionBlockDetail &&
    block.lastSeq < lastPromptSeq;

List<SessionBlock> resolveAnswered(List<SessionBlock> blocks, int throughSeq) => [
  for (final block in blocks)
    if (_isBlockedPermission(block) && block.lastSeq <= throughSeq) _answered(block) else block,
];

bool _isBlockedPermission(SessionBlock block) =>
    block.kind == BlockKind.permission && block.status == BlockStatus.blocked;

SessionBlock _answered(SessionBlock block) {
  if (block.kind != BlockKind.permission) return block;
  final toolName = block.toolName ?? '';
  return block.copyWith(
    kind: BlockKind.tool,
    title: toolName.isNotEmpty ? toolName : 'Tool',
    status: block.status == BlockStatus.blocked ? BlockStatus.ok : null,
  );
}

void _answerBlocked(List<SessionBlock> blocks, int seq) {
  for (var i = 0; i < blocks.length; i++) {
    if (_isBlockedPermission(blocks[i])) blocks[i] = _answered(blocks[i]).copyWith(lastSeq: seq);
  }
}

String? _soleRunningTool(List<SessionBlock> blocks, String? toolName) {
  if (toolName == null || toolName.isEmpty) return null;
  String? found;
  for (final block in blocks) {
    if (block.kind != BlockKind.tool || block.status != BlockStatus.running || block.toolName != toolName) continue;
    if (found != null) return null;
    found = block.id;
  }
  return found;
}

List<SessionBlock> resolveStranded(List<SessionBlock> blocks, String reason) => blocks
    .map(
      (block) => block.status == BlockStatus.running || block.status == BlockStatus.blocked
          ? block.copyWith(status: BlockStatus.failed, body: reason)
          : block,
    )
    .toList();

String _join(List<String> parts, String separator) => parts.where((part) => part.isNotEmpty).join(separator);

String? _correlationKey(BlockEventModel event) {
  final toolUse = event.toolUseId ?? '';
  if (toolUse.isNotEmpty) return toolUse;
  if (event.source == 'hook' && _sessionScopedHookKinds.contains(event.kind)) return null;
  final source = event.sourceId ?? '';
  return source.isNotEmpty ? source : null;
}

const _sessionScopedHookKinds = {'permission_request', 'question_asked'};

bool _isRedacted(BlockEventModel event) => (event.redactedSpans ?? const []).isNotEmpty;

String _blockId(BlockEventModel event, String? key) =>
    key != null && _correlates(event.kind) ? 'src-$key' : 'seq-${event.seq}';

const _correlatingKinds = {
  'tool_complete',
  'tool_start',
  'tool_result',
  'permission_request',
  'permission_replied',
  'question_asked',
  'compaction',
  'todo',
  'assistant_text',
  'reasoning',
  'agent_start',
  'agent_stop',
};

bool _correlates(String? kind) => _correlatingKinds.contains(kind);

SessionBlock _create(
  BlockEventModel event,
  String id,
  BlockKind kind,
  BlockStatus status,
  String title,
  String body,
  String? model, {
  String? result,
  BlockDetail? detail,
}) => SessionBlock(
  id: id,
  firstSeq: event.seq!,
  lastSeq: event.seq!,
  kind: kind,
  status: status,
  title: title,
  body: body,
  result: result,
  model: model,
  toolName: event.toolName,
  errorType: event.errorType,
  truncatedLines: event.truncatedLines ?? 0,
  redacted: _isRedacted(event),
  createdAt: event.createdAt,
  turnId: null,
  detail: detail ?? (event.toolName == 'Agent' ? AgentBlockDetail.fromToolInput(event.toolInput) : null) ?? UnknownBlockDetail(raw: event.toolInput ?? event.text ?? ''),
  interactionId: event.interactionId,
  agentId: (event.agentId ?? '').isEmpty ? null : event.agentId,
);

void _upsert(List<SessionBlock> blocks, Map<String, int> indexById, SessionBlock block) {
  final at = indexById[block.id];
  if (at != null) {
    blocks[at] = blocks[at].copyWith(body: block.body, status: block.status, lastSeq: block.lastSeq);
    return;
  }
  indexById[block.id] = blocks.length;
  blocks.add(block);
}

Map<String, dynamic> _decodeMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

int? _lastRunningPrompt(List<SessionBlock> blocks) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].kind == BlockKind.prompt && blocks[i].status == BlockStatus.running) return i;
  }
  return null;
}
