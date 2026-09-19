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
  String? source,
  String? interactionId,
  String? detail,
  String? agentId,
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
  source: source,
  interactionId: interactionId,
  detail: detail,
  agentId: agentId,
);

String _question(String question) =>
    '{"questions":[{"question":"$question","header":"H","options":[{"label":"main"}]}]}';

void main() {
  _unknownKindTests();
  group('assembleBlocks', () {
    test('a new prompt clears an obsolete waiting notice', () {
      final blocks = assembleBlocks([
        _event(1, 'question_asked', text: 'Waiting on you'),
        _event(2, 'prompt_submit', text: 'Hi'),
      ]);

      expect(blocks.map((block) => block.kind), [BlockKind.prompt]);
    });

    test('a prompt is running until its stop arrives', () {
      final open = assembleBlocks([_event(1, 'prompt_submit', text: 'go')]);
      expect(open.single.status, BlockStatus.running);

      final closed = assembleBlocks([_event(1, 'prompt_submit', text: 'go'), _event(2, 'stop', text: 'done')]);
      expect(closed.first.status, BlockStatus.ok);
      expect(closed.last.kind, BlockKind.assistant);
      expect(closed.last.body, 'done');
    });

    test('hook blocks keep their fields while gaining null turn ids and unknown details', () {
      final block = assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'ok')]).single;

      expect(block.id, 'seq-1');
      expect(block.kind, BlockKind.tool);
      expect(block.status, BlockStatus.ok);
      expect(block.title, 'Bash');
      expect(block.body, 'ok');
      expect(block.turnId, isNull);
      expect(block.detail, const UnknownBlockDetail(raw: 'ok'));
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
      final blocks = assembleBlocks([_event(1, 'prompt_submit', text: 'go'), _event(2, 'stop')]);

      expect(blocks, hasLength(1));
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('a stop with no open prompt still records the assistant text', () {
      final blocks = assembleBlocks([_event(1, 'stop', text: 'orphan')]);

      expect(blocks.single.kind, BlockKind.assistant);
      expect(blocks.single.body, 'orphan');
    });

    test('a transcript assistant_text landing after the stop hook replaces its block instead of twinning it', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'whats up'),
        _event(2, 'stop', text: 'Not much.'),
        _event(3, 'turn_model', text: 'claude-sonnet-5', source: 'transcript'),
        _event(4, 'assistant_text', sourceId: 'a1', text: 'Not much.', source: 'transcript'),
      ]);

      expect(blocks.where((b) => b.kind == BlockKind.assistant), hasLength(1));
      expect(blocks.last.body, 'Not much.');
      expect(blocks.last.model, 'claude-sonnet-5');
      expect(blocks.first.status, BlockStatus.ok);
    });

    test('a later transcript assistant_text in the same turn still appends', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'stop', text: 'final'),
        _event(3, 'assistant_text', sourceId: 'a1', text: 'first', source: 'transcript'),
        _event(4, 'assistant_text', sourceId: 'a2', text: 'final', source: 'transcript'),
      ]);

      expect(blocks.where((b) => b.kind == BlockKind.assistant).map((b) => b.body), ['first', 'final']);
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

    test('session_start produces no block', () {
      expect(assembleBlocks([_event(1, 'session_start', text: 'Session started')]), isEmpty);
    });

    test('a hook question is not shown as a "Waiting on you" divider', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'question_asked', sourceId: 'native-1', source: 'hook', text: 'Which branch?'),
      ]);

      expect(blocks.map((block) => block.title).toList(), ['Prompt']);
    });

    test('a transcript question without tool input blocks the session', () {
      final blocks = assembleBlocks([_event(1, 'question_asked', sourceId: 'q', source: 'transcript')]);

      expect(blocks.single.kind, BlockKind.notice);
      expect(blocks.single.status, BlockStatus.blocked);
      expect(blocks.single.title, 'Waiting on you');
    });

    test('a question left unanswered when the session dies does not stay pending', () {
      final blocks = assembleBlocks([_event(1, 'question_asked', sourceId: 'q', source: 'transcript')]);

      expect(resolveStranded(blocks, 'Session ended').single.status, BlockStatus.failed);
    });

    test('an unknown kind contributes no block', () {
      // This replaces an earlier rule that rendered "unknown" as a notice
      // titled by its raw event, for forward compatibility. That rule surfaced
      // hook payloads as chat messages: an unmapped subagent-stop put the
      // terminal composer's draft on the phone as a message from the agent.
      // Forward compatibility is still covered, by the unrecognised-kind test
      // below — "unknown" is the daemon's own marker for an event with no
      // meaning in the vocabulary, which is not the same as new content.
      final blocks = assembleBlocks([_event(1, 'unknown', rawEvent: 'future-hook', text: 'body')]);

      expect(blocks, isEmpty);
    });

    test('an unknown kind with no raw event contributes no block', () {
      expect(assembleBlocks([_event(1, 'unknown')]), isEmpty);
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
      expect(assembleBlocks([_event(1, 'tool_complete', toolName: 'Bash', text: 'a.txt')]).single.body, 'a.txt');
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

    test('a todo sourceId replayed across turns does not leave todoIndex past the end', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'todo', sourceId: 'a', text: 'first list'),
        _event(3, 'stop'),
        _event(4, 'prompt_submit', text: 'go again'),
        _event(5, 'todo', sourceId: 'a', text: 'replayed list'),
        _event(6, 'todo', sourceId: 'b', text: 'new list'),
      ]);

      final todos = blocks.where((b) => b.kind == BlockKind.todo).toList();
      expect(todos, hasLength(1));
      expect(todos.single.id, 'src-a');
      expect(todos.single.body, 'new list');
    });

    test('a replayed transcript question updates in place while a distinct one appends', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'question_asked', sourceId: 'q', text: 'Pick a branch?', source: 'transcript'),
        _event(3, 'prompt_submit', text: 'go again'),
        _event(4, 'question_asked', sourceId: 'q', text: 'Pick a branch again?', source: 'transcript'),
        _event(5, 'question_asked', sourceId: 'r', text: 'A new question', source: 'transcript'),
      ]);

      final questions = blocks.where((b) => b.status == BlockStatus.blocked).toList();
      expect(questions.map((question) => question.id).toList(), ['src-q', 'src-r']);
    });

    test('a second transcript question in one turn keeps the first', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'question_asked', sourceId: 'q1', toolUseId: 'q1', source: 'transcript', toolInput: _question('First?')),
        _event(3, 'tool_result', sourceId: 'q1', toolUseId: 'q1', source: 'transcript', text: 'main'),
        _event(4, 'question_asked', sourceId: 'q2', toolUseId: 'q2', source: 'transcript', toolInput: _question('Second?')),
      ]);

      expect(blocks.map((block) => block.title).toList(), ['Prompt', 'First?', 'Second?']);
      expect(blocks[1].status, BlockStatus.ok);
      expect(blocks[1].result, 'main');
      expect(blocks[2].status, BlockStatus.blocked);
    });

    test('a real AskUserQuestion collapses to one answerable question block', () {
      final blocks = assembleBlocks([
        _event(0, 'question_asked', sourceId: 'native-p', source: 'hook'),
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_q', toolUseId: 'toolu_q', toolName: 'AskUserQuestion', source: 'hook', toolInput: _question('Which colour?')),
        _event(3, 'permission_request', sourceId: 'native-p', toolName: 'AskUserQuestion', source: 'hook', toolInput: _question('Which colour?'), interactionId: 'i-q'),
        _event(4, 'question_asked', sourceId: 'toolu_q', toolUseId: 'toolu_q', toolName: 'AskUserQuestion', source: 'transcript', toolInput: _question('Which colour?')),
        _event(5, 'question_asked', sourceId: 'native-p', source: 'hook'),
      ]);

      expect(blocks.map((block) => block.title).toList(), ['Prompt', 'Which colour?']);
      final question = blocks.last;
      expect(question.detail, isA<QuestionBlockDetail>());
      expect(question.status, BlockStatus.blocked);
      expect(question.interactionId, 'i-q');
    });

    test('a permission request keeps its interaction id when the tool block already exists', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_b', toolUseId: 'toolu_b', toolName: 'Bash', source: 'hook'),
        _event(3, 'permission_request', sourceId: 'toolu_b', toolUseId: 'toolu_b', toolName: 'Bash', source: 'hook', interactionId: 'i-b'),
      ]);

      expect(blocks.last.kind, BlockKind.permission);
      expect(blocks.last.interactionId, 'i-b');
    });

    test('the hook notice is replaced in place and only once', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'question_asked', sourceId: 'native-1', source: 'hook', text: 'Waiting on you'),
        _event(3, 'question_asked', sourceId: 'q1', toolUseId: 'q1', source: 'transcript', toolInput: _question('First?')),
        _event(4, 'question_asked', sourceId: 'q2', toolUseId: 'q2', source: 'transcript', toolInput: _question('Second?')),
      ]);

      expect(blocks.map((block) => block.title).toList(), ['Prompt', 'First?', 'Second?']);
    });

    test('a transcript question enriching a hook placeholder preserves its interaction id', () {
      final blocks = assembleBlocks([
        _event(1, 'question_asked', sourceId: 'native-1', source: 'hook', text: 'Waiting on you', interactionId: 'i1'),
        _event(2, 'question_asked', sourceId: 'q1', toolUseId: 'q1', source: 'transcript', toolInput: _question('First?')),
      ]);

      expect(blocks.single.interactionId, 'i1');
    });

    test('a later TodoWrite folds into the first todo block and its result is dropped', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'todo', sourceId: 't1', toolUseId: 't1', source: 'transcript', text: 'first list'),
        _event(3, 'tool_result', sourceId: 't1', toolUseId: 't1', source: 'transcript', text: 'Todos have been modified'),
        _event(4, 'todo', sourceId: 't2', toolUseId: 't2', source: 'transcript', text: 'second list'),
        _event(5, 'tool_result', sourceId: 't2', toolUseId: 't2', source: 'transcript', text: 'Todos have been modified'),
      ]);

      expect(blocks.map((block) => block.kind).toList(), [BlockKind.prompt, BlockKind.todo]);
      expect(blocks.last.body, 'second list');
      expect(blocks.last.result, isNull);
    });

    test('the tool input is opaque text and is never parsed', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_complete', toolName: 'Write', toolInput: '{"content":"a[... truncated by Operator ...]b"'),
      ]);

      expect(blocks.single.body, contains('truncated by Operator'));
    });

    test('a permission event carries its interaction id onto the block', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 't1', interactionId: 'i1'),
      ]);

      expect(blocks.single.interactionId, 'i1');
    });

    test('a block with no interaction id is not actionable', () {
      final blocks = assembleBlocks([_event(1, 'tool_start', sourceId: 't1')]);

      expect(blocks.single.interactionId, isNull);
    });

    test('the transcript merge preserves the hook-supplied interaction id', () {
      final blocks = assembleBlocks([
        _event(1, 'permission_request', sourceId: 't1', interactionId: 'i1'),
        _event(2, 'tool_start', sourceId: 't1', source: 'transcript', toolInput: '{"command":"ls"}'),
      ]);

      expect(
        blocks.single.interactionId,
        'i1',
        reason: 'transcript wins on body, but it must not erase the id the hook supplied',
      );
    });
  });

  group('answered permissions', () {
    test('a hook permission without a tool use id adopts the running tool of the same name', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_r', toolUseId: 'toolu_r', toolName: 'Read', source: 'hook', toolInput: '{"file_path":"a"}'),
        _event(3, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
        _event(4, 'tool_start', sourceId: 'toolu_r', toolUseId: 'toolu_r', toolName: 'Read', source: 'transcript', toolInput: '{"file_path":"a"}'),
      ]);

      expect(blocks, hasLength(2));
      expect(blocks.last.id, 'src-toolu_r');
      expect(blocks.last.kind, BlockKind.permission);
      expect(blocks.last.status, BlockStatus.blocked);
      expect(blocks.last.interactionId, 'i1');
      expect(blocks.last.body, '{"file_path":"a"}');
    });

    test('the completion of the adopted tool answers the permission', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_r', toolUseId: 'toolu_r', toolName: 'Read', source: 'hook'),
        _event(3, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
        _event(4, 'tool_complete', sourceId: 'toolu_r', toolUseId: 'toolu_r', toolName: 'Read', source: 'hook'),
      ]);

      expect(blocks, hasLength(2));
      expect(blocks.last.kind, BlockKind.tool);
      expect(blocks.last.status, BlockStatus.ok);
      expect(blocks.last.title, 'Read');
    });

    test('a denied permission is answered by the tool result that reports the refusal', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_r', toolUseId: 'toolu_r', toolName: 'Bash', source: 'hook'),
        _event(3, 'permission_request', sourceId: 'agent-1', toolName: 'Bash', source: 'hook', interactionId: 'i1'),
        _event(4, 'tool_result', sourceId: 'toolu_r', toolUseId: 'toolu_r', source: 'transcript', text: 'User denied', errorType: 'tool_failed'),
      ]);

      expect(blocks.last.kind, BlockKind.tool);
      expect(blocks.last.status, BlockStatus.failed);
    });

    test('an ambiguous tool name leaves the permission uncorrelated', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Read', source: 'hook'),
        _event(3, 'tool_start', sourceId: 'toolu_b', toolUseId: 'toolu_b', toolName: 'Read', source: 'hook'),
        _event(4, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
      ]);

      expect(blocks.map((block) => block.id), ['seq-1', 'src-toolu_a', 'src-toolu_b', 'seq-4']);
      expect(blocks.last.status, BlockStatus.blocked);
    });

    test('a turn boundary answers every permission still blocked', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
        _event(3, 'stop', sourceId: 'agent-1', source: 'hook'),
      ]);

      expect(blocks[1].kind, BlockKind.tool);
      expect(blocks[1].status, BlockStatus.ok);
      expect(blocks[1].title, 'Read');
    });

    test('a new prompt answers a permission left over from the previous turn', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
        _event(3, 'prompt_submit', text: 'again'),
      ]);

      expect(blocks[1].status, BlockStatus.ok);
      expect(blocks[1].kind, BlockKind.tool);
    });

    test('resolveAnswered answers blocked permissions up to a sequence and no further', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', text: 'go'),
        _event(2, 'permission_request', sourceId: 'agent-1', toolName: 'Read', source: 'hook', interactionId: 'i1'),
        _event(3, 'permission_request', sourceId: 'agent-1', toolName: 'Bash', source: 'hook', interactionId: 'i2'),
      ]);

      final resolved = resolveAnswered(blocks, 2);

      expect(resolved[0].status, BlockStatus.running);
      expect(resolved[1].kind, BlockKind.tool);
      expect(resolved[1].status, BlockStatus.ok);
      expect(resolved[2].kind, BlockKind.permission);
      expect(resolved[2].status, BlockStatus.blocked);
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

  group('agents', () {
    const input = '{"description":"Implement Task 1","prompt":"You are implementing Task 1","model":"haiku","run_in_background":true}';

    test('an Agent tool block carries its description, prompt and model', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.description, 'Implement Task 1');
      expect(detail.prompt, 'You are implementing Task 1');
      expect(detail.model, 'haiku');
      expect(detail.status, 'running');
      expect(blocks.single.status, BlockStatus.running);
    });

    test('the Agent result merges the agent identity and totals', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
        _event(2, 'tool_result', sourceId: 'toolu_a', toolUseId: 'toolu_a', source: 'transcript', text: 'done',
            detail: '{"agentId":"a1","agentType":"general-purpose","status":"completed","resolvedModel":"claude-haiku-4-5","totalDurationMs":61000,"totalToolUseCount":7,"totalTokens":9000}'),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.agentId, 'a1');
      expect(detail.agentType, 'general-purpose');
      expect(detail.status, 'completed');
      expect(detail.durationMs, 61000);
      expect(detail.toolUseCount, 7);
      expect(detail.description, 'Implement Task 1');
      expect(blocks.single.status, BlockStatus.ok);
    });

    test('an agent_stop completes the Agent block it names', () {
      final blocks = assembleBlocks([
        _event(1, 'tool_start', sourceId: 'toolu_a', toolUseId: 'toolu_a', toolName: 'Agent', source: 'transcript', toolInput: input),
        _event(2, 'tool_result', sourceId: 'toolu_a', toolUseId: 'toolu_a', source: 'transcript', text: 'Async agent launched',
            detail: '{"agentId":"a1","agentType":"general-purpose","status":"running"}'),
        _event(3, 'agent_stop', sourceId: 'a1', agentId: 'a1', source: 'hook', text: 'finished'),
      ]);
      final detail = blocks.single.detail as AgentBlockDetail;
      expect(detail.status, 'completed');
    });

    test('agent-scoped events carry the agent id onto their blocks', () {
      final blocks = assembleBlocks([_event(1, 'prompt_submit', text: 'go', agentId: 'a1')]);
      expect(blocks.single.agentId, 'a1');
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

void _unknownKindTests() {
  group('unknown block events', () {
    test('an unknown kind contributes no block', () {
      // The daemon records an installed-but-unmapped hook as kind "unknown",
      // carrying whatever text the payload held. Rendering it as a notice put
      // the terminal composer's draft on screen as a chat message, titled
      // "subagent-stop".
      final blocks = assembleBlocks([
        _event(1, 'unknown', rawEvent: 'subagent-stop', text: 'search more on the Anthropic lawsuit'),
      ]);

      expect(blocks, isEmpty);
    });

    test('an unknown kind does not interrupt the blocks around it', () {
      final blocks = assembleBlocks([
        _event(1, 'prompt_submit', sourceId: 'p1', text: 'hello'),
        _event(2, 'unknown', rawEvent: 'pre-tool-use', text: 'noise'),
        _event(3, 'stop', sourceId: 'p1', text: 'done'),
      ]);

      expect(blocks.map((b) => b.kind), isNot(contains(BlockKind.notice)));
      expect(blocks.map((b) => b.body), isNot(contains('noise')));
      expect(blocks.first.kind, BlockKind.prompt);
    });

    test('a kind this build does not recognise still renders, for forward compatibility', () {
      // Distinct from "unknown": a newer daemon emitting a kind this client has
      // not learned yet is real content, and silence would hide it.
      final blocks = assembleBlocks([
        _event(1, 'some_future_kind', rawEvent: 'some-future-kind', text: 'real content'),
      ]);

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, BlockKind.notice);
    });
  });
}
