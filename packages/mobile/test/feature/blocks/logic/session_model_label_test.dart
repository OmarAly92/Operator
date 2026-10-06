import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/logic/session_model_label.dart';

SessionBlock _block(String id, int seq, {String? model}) => SessionBlock(
  id: id,
  firstSeq: seq,
  lastSeq: seq,
  kind: BlockKind.assistant,
  status: BlockStatus.ok,
  title: 'Assistant',
  body: 'hi',
  model: model,
);

void main() {
  test('the session command model wins', () {
    expect(
      sessionModelLabel(currentModel: 'Opus 5', blocks: [_block('a', 1, model: 'claude-sonnet-5')]),
      'Opus 5',
    );
  });

  test('falls back to the latest block that names a model, formatted', () {
    expect(
      sessionModelLabel(
        currentModel: null,
        blocks: [
          _block('a', 1, model: 'claude-haiku-4-5'),
          _block('b', 2, model: 'claude-sonnet-5'),
          _block('c', 3),
          _block('d', 4, model: ''),
        ],
      ),
      'Sonnet 5',
    );
  });

  test('is null when nothing names a model', () {
    expect(sessionModelLabel(currentModel: null, blocks: [_block('a', 1)]), isNull);
    expect(sessionModelLabel(currentModel: null, blocks: const []), isNull);
  });
}
