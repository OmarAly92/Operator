import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

List<SessionBlock> assembleBlocks(Iterable<BlockEventModel> events) {
  final ordered = events.where((event) => event.seq != null).toList()..sort((a, b) => a.seq!.compareTo(b.seq!));

  final blocks = <SessionBlock>[];
  final indexById = <String, int>{};
  final consumed = <int>{};

  for (final event in ordered) {
    final seq = event.seq!;
    if (!consumed.add(seq)) continue;

    final key = _correlationKey(event);
    final text = event.text ?? '';

    switch (event.kind) {
      case 'idle_prompt':
        continue;

      case 'session_start':
        _append(blocks, indexById, _create(event, key, BlockKind.notice, BlockStatus.ok, 'Session started', text));

      case 'prompt_submit':
        _append(blocks, indexById, _create(event, key, BlockKind.prompt, BlockStatus.running, 'Prompt', text));

      case 'tool_complete':
        final failed = (event.errorType ?? '').isNotEmpty;
        final status = failed ? BlockStatus.failed : BlockStatus.ok;
        final body = _join([event.toolInput ?? '', text], '\n\n');
        final at = key == null ? null : indexById['src-$key'];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(
            status: status,
            body: body,
            lastSeq: seq,
            errorType: event.errorType,
            truncatedLines: event.truncatedLines ?? 0,
            redacted: _isRedacted(event),
          );
        } else {
          _append(blocks, indexById, _create(event, key, BlockKind.tool, status, event.toolName ?? 'Tool', body));
        }

      case 'permission_request':
        final detail = (event.toolInput ?? '').isNotEmpty ? event.toolInput! : text;
        final body = _join([event.toolName ?? '', detail], '\n');
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.permission, BlockStatus.blocked, 'Permission requested', body),
        );

      case 'question_asked':
        _append(blocks, indexById, _create(event, key, BlockKind.notice, BlockStatus.blocked, 'Waiting on you', text));

      case 'permission_replied':
        final at = key == null ? null : indexById['src-$key'];
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: BlockStatus.ok, lastSeq: seq);
        }

      case 'stop':
      case 'stop_failure':
        final failed = event.kind == 'stop_failure';
        final at = _lastRunningPrompt(blocks);
        if (at != null) {
          blocks[at] = blocks[at].copyWith(status: failed ? BlockStatus.failed : BlockStatus.ok, lastSeq: seq);
        }
        if (text.isNotEmpty) {
          _append(
            blocks,
            indexById,
            _create(event, key, BlockKind.assistant, failed ? BlockStatus.failed : BlockStatus.ok, 'Assistant', text),
          );
        }

      default:
        final raw = event.rawEvent ?? '';
        _append(
          blocks,
          indexById,
          _create(event, key, BlockKind.notice, BlockStatus.ok, raw.isNotEmpty ? raw : 'Event', text),
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

SessionBlock _create(
  BlockEventModel event,
  String? key,
  BlockKind kind,
  BlockStatus status,
  String title,
  String body,
) {
  final correlated = key != null && _correlates(event.kind);
  return SessionBlock(
    id: correlated ? 'src-$key' : 'seq-${event.seq}',
    firstSeq: event.seq!,
    lastSeq: event.seq!,
    kind: kind,
    status: status,
    title: title,
    body: body,
    toolName: event.toolName,
    errorType: event.errorType,
    truncatedLines: event.truncatedLines ?? 0,
    redacted: _isRedacted(event),
    createdAt: event.createdAt,
    turnId: null,
    detail: UnknownBlockDetail(raw: event.toolInput ?? event.text ?? ''),
  );
}

bool _correlates(String? kind) =>
    kind == 'tool_complete' || kind == 'permission_request' || kind == 'permission_replied';

void _append(List<SessionBlock> blocks, Map<String, int> indexById, SessionBlock block) {
  indexById[block.id] = blocks.length;
  blocks.add(block);
}

int? _lastRunningPrompt(List<SessionBlock> blocks) {
  for (var i = blocks.length - 1; i >= 0; i--) {
    if (blocks[i].kind == BlockKind.prompt && blocks[i].status == BlockStatus.running) return i;
  }
  return null;
}
