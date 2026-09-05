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
  var sawTranscriptAssistant = false;

  for (final event in ordered) {
    final seq = event.seq!;
    if (!consumed.add(seq)) continue;

    final key = _correlationKey(event);
    final id = _blockId(event, key);
    final text = event.text ?? '';
    final fromTranscript = event.source == 'transcript';

    switch (event.kind) {
      case 'idle_prompt':
        continue;

      case 'session_start':
        _upsert(blocks, indexById, _create(event, id, BlockKind.notice, BlockStatus.ok, 'Session started', text, model));

      case 'prompt_submit':
        todoIndex = null;
        questionIndex = null;
        hookQuestionIndex = null;
        sawTranscriptAssistant = false;
        _upsert(blocks, indexById, _create(event, id, BlockKind.prompt, BlockStatus.running, 'Prompt', text, model));

      case 'turn_model':
        if (text.isNotEmpty) model = text;

      case 'assistant_text':
        sawTranscriptAssistant = true;
        final title = event.rawEvent == 'commentary' ? 'Assistant · note' : 'Assistant';
        _upsert(blocks, indexById, _create(event, id, BlockKind.assistant, BlockStatus.ok, title, text, model));

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
          blocks[at] = target.copyWith(
            result: target.kind == BlockKind.todo ? null : text,
            lastSeq: seq,
            errorType: event.errorType,
            status: statusFromHook.contains(id) ? null : resolved,
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
          blocks[at] = blocks[at].copyWith(
            status: status,
            body: bodyFromTranscript.contains(id) ? null : hookBody,
            lastSeq: seq,
            errorType: event.errorType,
            truncatedLines: event.truncatedLines ?? 0,
            redacted: _isRedacted(event) || blocks[at].redacted,
          );
        } else {
          _upsert(
            blocks,
            indexById,
            _create(event, id, BlockKind.tool, status, event.toolName ?? 'Tool', hookBody, model),
          );
        }

      case 'permission_request':
        statusFromHook.add(id);
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            kind: BlockKind.permission,
            title: 'Permission requested',
            status: BlockStatus.blocked,
            lastSeq: seq,
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

      case 'question_asked':
        final questions = fromTranscript ? parseQuestionDetail(event.toolInput ?? '') : null;
        if (!fromTranscript && questionIndex != null) continue;
        final title = questions?.questions.first.question ?? 'Waiting on you';
        final body = fromTranscript ? '' : text;
        final block = _create(event, id, BlockKind.notice, BlockStatus.blocked, title, body, model, detail: questions);
        if (fromTranscript && hookQuestionIndex != null) {
          indexById.remove(blocks[hookQuestionIndex].id);
          blocks[hookQuestionIndex] = block;
          indexById[block.id] = hookQuestionIndex;
          questionIndex = hookQuestionIndex;
          hookQuestionIndex = null;
        } else {
          _upsert(blocks, indexById, block);
          questionIndex = indexById[block.id];
          if (!fromTranscript) hookQuestionIndex = questionIndex;
        }

      case 'permission_replied':
        final at = indexById[id];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: BlockStatus.ok, lastSeq: seq);
        }

      case 'stop':
      case 'stop_failure':
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
        }

      case 'unknown':
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

  return blocks;
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
  final source = event.sourceId ?? '';
  if (source.isNotEmpty) return source;
  final toolUse = event.toolUseId ?? '';
  return toolUse.isNotEmpty ? toolUse : null;
}

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
  detail: detail ?? UnknownBlockDetail(raw: event.toolInput ?? event.text ?? ''),
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

int? _lastRunningPrompt(List<SessionBlock> blocks) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].kind == BlockKind.prompt && blocks[i].status == BlockStatus.running) return i;
  }
  return null;
}
