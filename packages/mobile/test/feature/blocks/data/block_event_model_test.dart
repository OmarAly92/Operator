import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/get_session_blocks_params.dart';

void main() {
  test('parses a full record', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 7,
      'sessionId': 's-1',
      'sourceId': 'tu-1',
      'kind': 'tool_complete',
      'harness': 'claude-code',
      'toolName': 'Bash',
      'toolUseId': 'tu-1',
      'text': 'token=[redacted]',
      'toolInput': '{"command":"ls -la"}',
      'errorType': 'tool_failed',
      'hookVersion': '1',
      'redactedSpans': [
        {'start': 6, 'end': 16},
      ],
      'truncatedLines': 3,
      'createdAt': '2026-08-27T10:00:00Z',
    });

    expect(model.seq, 7);
    expect(model.kind, 'tool_complete');
    expect(model.toolUseId, 'tu-1');
    expect(model.toolInput, '{"command":"ls -la"}');
    expect(model.errorType, 'tool_failed');
    expect(model.hookVersion, '1');
    expect(model.truncatedLines, 3);
    expect(model.redactedSpans, hasLength(1));
    expect(model.redactedSpans!.single.start, 6);
    expect(model.redactedSpans!.single.end, 16);
    expect(model.createdAt, '2026-08-27T10:00:00Z');
  });

  test('parses a record whose optional fields are all absent', () {
    final model = BlockEventModel.fromJson(const {'seq': 1, 'kind': 'stop'});

    expect(model.seq, 1);
    expect(model.kind, 'stop');
    expect(model.toolName, isNull);
    expect(model.toolInput, isNull);
    expect(model.errorType, isNull);
    expect(model.redactedSpans, isNull);
    expect(model.truncatedLines, isNull);
  });

  test('carries an unknown kind through with its raw event name', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 2,
      'kind': 'unknown',
      'rawEvent': 'some-future-hook',
    });

    expect(model.kind, 'unknown');
    expect(model.rawEvent, 'some-future-hook');
  });

  test('reads the blocks envelope', () {
    final models = BlockEventModel.listFromJson(const {
      'blocks': [
        {'seq': 1, 'kind': 'prompt_submit'},
        {'seq': 2, 'kind': 'stop'},
      ],
    });

    expect(models.map((m) => m.seq), [1, 2]);
  });

  test('an absent blocks envelope is an empty list, not a crash', () {
    expect(BlockEventModel.listFromJson(const {}), isEmpty);
  });

  test('params omit the keys the caller did not set', () {
    expect(const GetSessionBlocksParams().toJson(), isEmpty);
    expect(const GetSessionBlocksParams(afterSeq: 4).toJson(), {'afterSeq': 4});
    expect(
      const GetSessionBlocksParams(afterSeq: 4, limit: 50).toJson(),
      {'afterSeq': 4, 'limit': 50},
    );
    expect(
      const GetSessionBlocksParams(beforeSeq: 9, limit: 50).toJson(),
      {'beforeSeq': 9, 'limit': 50},
    );
  });

  test('reads the source channel off the wire', () {
    final model = BlockEventModel.fromJson(const {
      'seq': 1,
      'sessionId': 's-1',
      'kind': 'assistant_text',
      'source': 'transcript',
      'text': 'hello',
    });

    expect(model.source, 'transcript');
  });

  test('a record with no source parses with a null source', () {
    final model = BlockEventModel.fromJson(const {'seq': 1, 'kind': 'stop'});

    expect(model.source, isNull);
  });
}
