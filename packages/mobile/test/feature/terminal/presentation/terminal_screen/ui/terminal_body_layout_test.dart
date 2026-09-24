import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/chat_insets.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';

import '../../../terminal_harness.dart';

List<BlockEventModel> _conversation(int turns) => [
  for (var turn = 0; turn < turns; turn++) ...[
    BlockEventModel(seq: turn * 2 + 1, sessionId: 's-1', sourceId: 'p$turn', kind: 'prompt_submit', text: 'prompt $turn'),
    BlockEventModel(
      seq: turn * 2 + 2,
      sessionId: 's-1',
      sourceId: 'a$turn',
      kind: 'assistant_text',
      text: 'reply $turn with enough words to fill a line or two of the transcript',
    ),
  ],
];

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SendSessionMessageParams(message: '')));

  tearDown(() => harness.dispose());

  Rect capsule(WidgetTester tester) => tester.getRect(find.byKey(TerminalComposer.capsuleKey));

  testWidgets('the transcript runs under the floating capsule and its last message clears it', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(12));
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(BlockList));
    final dock = capsule(tester);
    expect(list.bottom, greaterThan(dock.bottom));

    final state = tester.state<BlockListState>(find.byType(BlockList));
    expect(state.pinned, isTrue);
    final lastReply = tester.getRect(find.textContaining('reply 11'));
    expect(lastReply.bottom, lessThanOrEqualTo(dock.top));
  });

  testWidgets('the capsule floats 8pt in from the sides and 8pt above the bottom', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(2));
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    final body = tester.getRect(find.byType(TerminalBody));
    final dock = capsule(tester);
    expect(dock.left - body.left, 8);
    expect(body.right - dock.right, 8);
    expect(body.bottom - dock.bottom, 8);
  });

  testWidgets('a growing composer publishes its height and keeps the last message clear', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(12));
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();
    final resting = tester.widget<ChatInsets>(find.byType(ChatInsets)).bottom.value;

    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await tester.pumpAndSettle();

    final grown = tester.widget<ChatInsets>(find.byType(ChatInsets)).bottom.value;
    expect(grown, greaterThan(resting));
    final body = tester.getRect(find.byType(TerminalBody));
    expect(grown, body.bottom - capsule(tester).top);
    expect(tester.getRect(find.textContaining('reply 11')).bottom, lessThanOrEqualTo(capsule(tester).top));
  });

  testWidgets('the raw terminal ends above the dock instead of running under it', (tester) async {
    harness = TerminalHarness()..start();
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    final pane = tester.getRect(find.byType(RawTerminalPane));
    final insets = tester.widget<ChatInsets>(find.byType(ChatInsets)).bottom.value;
    final body = tester.getRect(find.byType(TerminalBody));
    expect(pane.bottom, body.bottom - insets);
  });

  testWidgets('stop asks to kill the session before anything happens', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(1));
    harness.commandCubit.onActivity('active');
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Stop'));
    await tester.pumpAndSettle();

    expect(find.text('Kill session?'), findsOneWidget);
    verifyNever(() => harness.sessionsRepository.kill(any()));
  });
}
