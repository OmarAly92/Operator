import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/terminal/logic/working_since.dart';

SessionBlock _prompt(String createdAt) => SessionBlock(
  id: 'p-1',
  turnId: 't-1',
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.prompt,
  status: BlockStatus.ok,
  title: 'You',
  body: 'go',
  createdAt: createdAt,
);

void main() {
  const marked = '2026-09-23T12:00:00Z';
  const prompted = '2026-09-23T12:00:05Z';

  test('the daemon activity timestamp wins', () {
    const sessions = [SessionModel(id: 's-1', activity: 'active', activitySince: marked)];

    expect(
      workingSince(sessions: sessions, sessionId: 's-1', blocks: [_prompt(prompted)]),
      DateTime.parse(marked),
    );
  });

  test('without it the latest turn start is used', () {
    expect(
      workingSince(sessions: const [], sessionId: 's-1', blocks: [_prompt(prompted)]),
      DateTime.parse(prompted),
    );
  });

  test('with neither there is no start', () {
    expect(workingSince(sessions: const [], sessionId: 's-1', blocks: const []), isNull);
  });
}
