import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/block_assembly.dart';
import 'package:operator_mobile/feature/blocks/logic/block_harnesses.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';

BlockEventModel _event(
  int seq,
  String kind, {
  String? sourceId,
  String? toolName,
  String? toolUseId,
  String? text,
  String? toolInput,
  String? errorType,
  String? rawEvent,
  int? truncatedLines,
  List<BlockRedactedSpanModel>? spans,
}) => BlockEventModel(
  seq: seq,
  sessionId: 's-1',
  kind: kind,
  sourceId: sourceId,
  toolName: toolName,
  toolUseId: toolUseId,
  text: text,
  toolInput: toolInput,
  errorType: errorType,
  rawEvent: rawEvent,
  truncatedLines: truncatedLines,
  redactedSpans: spans,
);

void main() {
  group('assembleBlocks', () {
    test('a prompt is running until its stop arrives', () {
      final open = assembleBlocks([_event(1, 'prompt_submit', text: 'go')]);
      expect(open.single.status, BlockStatus.running);

      final closed = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop', text: 'done'),
      ]);
      expect(closed.first.status, BlockStatus.ok);
      expect(closed.last.kind, BlockKind.assistant);
      expect(closed.last.body, 'done');
    });

    test('stop_failure fails the open prompt and its assistant block', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop_failure', text: 'crashed'),
      ]);

      expect(blocks.first.status, BlockStatus.failed);
      expect(blocks.last.status, BlockStatus.failed);
    });

    test('a stop with no text resolves the prompt without adding a block', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('a stop with no open prompt still records the assistant text', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'orphan')]);

      expect(blocks.single.kind, BlockKind.assistant);
      expect(blocks.single.body, 'orphan');
    });

    test('only the most recent open prompt is resolved', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'first'),
        _event(2, 'prompt_submit', text: 'second'),
        _event(3, 'stop', text: 'done'),
      ]);

      expect(blocks[0].status, BlockStatus.running);
      expect(blocks[1].status, BlockStatus.ok);
    });

    test('a tool_complete correlates on sourceId rather than creating a twin', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'k', toolName: 'Bash', text: 'rm -rf'),
        _event(2, 'permission_replied', sourceId: 'k'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.id, 'src-k');
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('toolUseId is the fallback correlation key', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolUseId: 'tu-2', toolName: 'Bash', text: 'a'),
        _event(2, 'tool_complete', toolUseId: 'tu-2', toolName: 'Bash', text: 'b'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.body, 'b');
      expect(blocks.single.lastSeq, 2);
    });

    test('uncorrelated events each get their own block', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', text: 'a'),
        _event(2, 'tool_complete', toolName: 'Bash', text: 'b'),
      ]);

      expect(blocks.map((b) => b.id), ['seq-1', 'seq-2']);
    });

    test('idle_prompt produces nothing', () {
      expect(assembleBlocks([_event(1, 'idle_prompt')]), isEmpty);
    });

    test('a permission_replied with nothing to reply to produces nothing', () {
      expect(assembleBlocks([_event(1, 'permission_replied', sourceId: 'ghost')]), isEmpty);
    });

    test('a question blocks the session rather than reading as a benign notice', () {
      final blocks = assembleBlocks([_event(1, 'question_asked', text: 'Which branch?')]);

      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.status, BlockStatus.blocked);
      expect(blocks.single.title, 'Waiting on you');
      expect(blocks.single.body, 'Which branch?');
    });

    test('a question left unanswered when the session dies does not stay pending', () {
      final blocks = assembleBlocks([_event(1, 'question_asked', text: 'Which branch?')]);

      expect(resolveStranded(blocks, 'Session ended').single.status, BlockStatus.failed);
    });

    test('an unknown kind degrades to a notice titled by its raw event', () {
      final blocks = assembleBlocks([
        _event(1, 'unknown', rawEvent: 'future-hook', text: 'body'),
      ]);

      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.title, 'future-hook');
      expect(blocks.single.body, 'body');
    });

    test('an unknown kind with no raw event still renders', () {
      expect(assembleBlocks([_event(1, 'unknown')]).single.title, 'Event');
    });

    test('input order does not matter and duplicate seqs are dropped', () {
      final ordered = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(3, 'stop', text: 'done'),
      ]);
      final shuffled = assembleBlocks([
        _event(3, 'stop', text: 'done'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(2, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'out'),
        _event(1, 'prompt_submit', text: 'go'),
      ]);

      expect(shuffled, ordered);
    });

    test('an event with no seq is dropped rather than crashing', () {
      expect(assembleBlocks([const BlockEventModel(kind: 'stop', text: 'x')]), isEmpty);
    });

    test('truncation and redaction ride along', () {
      final blocks = assembleBlocks([
        _event(
          1,
          'tool_complete',
          sourceId: 'k',
          toolName: 'Read',
          text: 'k=[redacted]',
          truncatedLines: 900,
          spans: const [BlockRedactedSpanModel(start: 2, end: 12)],
        ),
      ]);

      expect(blocks.single.truncatedLines, 900);
      expect(blocks.single.redacted, isTrue);
    });

    test('multi-byte text survives assembly unchanged', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'héllo → 世界 🎉')]);

      expect(blocks.single.body, 'héllo → 世界 🎉');
    });

    test('a tool_complete with no name is still readable', () {
      expect(assembleBlocks([_event(1, 'tool_complete', text: 'x')]).single.title, 'Tool');
    });

    test('an errorType is what makes a tool block fail', () {
      final ok = assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'done')]);
      expect(ok.single.status, BlockStatus.ok);

      final failed = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', text: 'no such file', errorType: 'tool_failed'),
      ]);
      expect(failed.single.status, BlockStatus.failed);
      expect(failed.single.errorType, 'tool_failed');
    });

    test('a correlated failure flips an already-ok block', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'k', toolName: 'Bash', toolInput: 'rm -rf /'),
        _event(2, 'permission_replied', sourceId: 'k'),
        _event(3, 'tool_complete', sourceId: 'k', toolName: 'Bash', text: 'denied', errorType: 'tool_failed'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.status, BlockStatus.failed);
    });

    test('a tool block shows what ran before what came back', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Bash', toolInput: '{"command":"ls"}', text: 'a.txt'),
      ]);

      expect(blocks.single.body, '{"command":"ls"}\n\na.txt');
    });

    test('a tool block with only a result omits the blank separator', () {
      expect(
        assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'a.txt')]).single.body,
        'a.txt',
      );
    });

    test('a permission block names the tool and its input', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'p', toolName: 'Bash', toolInput: 'git push --force'),
      ]);

      expect(blocks.single.body, 'Bash\ngit push --force');
    });

    test('a permission block falls back to text when there is no input', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 'p', toolName: 'Bash', text: 'wants to run something'),
      ]);

      expect(blocks.single.body, 'Bash\nwants to run something');
    });

    test('the tool input is opaque text and is never parsed', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Write', toolInput: '{"content":"a[... truncated by Operator ...]b"'),
      ]);

      expect(blocks.single.body, contains('truncated by Operator'));
    });
  });

  group('resolveStranded', () {
    test('running and blocked become failed with the stated reason', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'permission_request', sourceId: 'k', toolName: 'Bash'),
        _event(3, 'tool_complete', sourceId: 'done', toolName: 'Bash', text: 'fine'),
      ]);

      final resolved = resolveStranded(blocks, 'Session exited');

      expect(resolved[0].status, BlockStatus.failed);
      expect(resolved[0].body, 'Session exited');
      expect(resolved[1].status, BlockStatus.failed);
      expect(resolved[2].status, BlockStatus.ok);
      expect(resolved[2].body, 'fine');
    });

    test('is a no-op when nothing is stranded', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'done')]);

      expect(resolveStranded(blocks, 'Session exited'), blocks);
    });
  });

  group('BlockHarnesses', () {
    test('covers the harnesses with registered mappers', () {
      expect(BlockHarnesses.covers('claude-code'), isTrue);
      expect(BlockHarnesses.covers('grok'), isTrue);
      expect(BlockHarnesses.covers('codex'), isTrue);
    });

    test('does not cover an unknown or absent harness', () {
      expect(BlockHarnesses.covers('aider'), isFalse);
      expect(BlockHarnesses.covers(null), isFalse);
      expect(BlockHarnesses.covers(''), isFalse);
    });
  });
}
