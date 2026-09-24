import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/widgets/chat/chat_insets.dart';
import 'package:operator_mobile/core/widgets/glass/frosted_header.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_find_bar.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/block_list.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/raw_terminal_pane.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart';

import '../../../terminal_harness.dart';

List<BlockEventModel> _conversation(int turns) => [
  for (var turn = 0; turn < turns; turn++) ...[
    BlockEventModel(
      seq: turn * 2 + 1,
      sessionId: 's-1',
      sourceId: 'p$turn',
      kind: 'prompt_submit',
      text: 'prompt $turn',
    ),
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

  setUpAll(() {
    registerFallbackValue(const SendSessionMessageParams(message: ''));
    registerFallbackValue(const SessionCommandParams(command: ''));
  });

  tearDown(() => harness.dispose());

  Finder header() => find.byType(TerminalChatHeader);

  double band(WidgetTester tester) => tester.widget<FrostedBand>(find.byKey(TerminalChatHeader.bandKey)).visibility;

  Finder frost() => find.descendant(of: header(), matching: find.byType(BackdropFilter));

  Future<void> open(WidgetTester tester, int turns) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(turns));
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, double Function(ScrollPosition position) target) async {
    final controller = tester.state<BlockListState>(find.byType(BlockList)).controller;
    controller.jumpTo(target(controller.position));
    await tester.pump();
  }

  testWidgets('the header is clear with the transcript at its top, and frosts over 16pt of scroll', (tester) async {
    await open(tester, 12);

    await scrollTo(tester, (position) => position.minScrollExtent);
    expect(band(tester), 0);
    expect(frost(), findsNothing);

    await scrollTo(tester, (position) => position.minScrollExtent + 8);
    expect(band(tester), closeTo(0.5, 0.001));
    expect(frost(), findsOneWidget);

    await scrollTo(tester, (position) => position.minScrollExtent + 16);
    expect(band(tester), 1);

    await scrollTo(tester, (position) => position.maxScrollExtent);
    expect(band(tester), 1);
  });

  testWidgets('a short chat that does not fill the screen shows no band', (tester) async {
    await open(tester, 1);

    expect(tester.state<BlockListState>(find.byType(BlockList)).pinned, isTrue);
    expect(band(tester), 0);
    expect(frost(), findsNothing);
  });

  testWidgets('the band draws a hairline at its bottom edge once it shows', (tester) async {
    await open(tester, 12);

    final bandWidget = tester.widget<FrostedBand>(find.byKey(TerminalChatHeader.bandKey));
    expect(bandWidget.hairline, isTrue);
  });

  testWidgets('the header publishes its height as the top inset', (tester) async {
    await open(tester, 1);

    final insets = tester.widget<ChatInsets>(find.byType(ChatInsets));
    expect(insets.top, tester.getRect(header()).height);
    expect(tester.getRect(header()).height, TerminalChatHeader.barHeight);
  });

  testWidgets('the first message sits below the header in a short chat', (tester) async {
    await open(tester, 1);

    expect(tester.getRect(find.text('prompt 0')).top, greaterThanOrEqualTo(tester.getRect(header()).bottom));
  });

  testWidgets('the first message sits below the header at the top of a long chat', (tester) async {
    await open(tester, 12);
    await scrollTo(tester, (position) => position.minScrollExtent);

    expect(tester.getRect(find.text('prompt 0')).top, greaterThanOrEqualTo(tester.getRect(header()).bottom));
  });

  testWidgets('the transcript runs under the header once scrolled', (tester) async {
    await open(tester, 12);

    expect(tester.getRect(find.byType(BlockList)).top, tester.getRect(find.byType(TerminalBody)).top);
  });

  testWidgets('the raw terminal starts below the header', (tester) async {
    harness = TerminalHarness()..start();
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(RawTerminalPane)).top, greaterThanOrEqualTo(tester.getRect(header()).bottom));
    expect(band(tester), 0);
  });

  testWidgets('the back button is a 38pt glass button that pops the route', (tester) async {
    harness = TerminalHarness()..start(harness: 'claude-code', blockRecords: _conversation(1));
    await harness.pump(
      tester,
      Navigator(
        onGenerateInitialRoutes: (navigator, _) => [
          MaterialPageRoute<void>(builder: (_) => const Text('sessions')),
          MaterialPageRoute<void>(builder: (_) => const TerminalBody()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final back = find.byKey(TerminalChatHeader.backKey);
    expect(tester.widget<GlassButton>(back).diameter, 38);
    expect(tester.getSize(back), const Size(38, 38));

    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(TerminalBody), findsNothing);
    expect(find.text('sessions'), findsOneWidget);
  });

  testWidgets('one glass capsule groups the activity pill, search and the terminal toggle', (tester) async {
    await open(tester, 1);

    final capsule = find.byKey(TerminalChatHeader.capsuleKey);
    expect(capsule, findsOneWidget);
    expect(find.descendant(of: capsule, matching: find.text('Idle')), findsOneWidget);
    expect(find.descendant(of: capsule, matching: find.byTooltip('Find in blocks')), findsOneWidget);
    expect(find.descendant(of: capsule, matching: find.bySemanticsLabel('Show raw terminal')), findsOneWidget);
  });

  testWidgets('the raw terminal keeps the pill and toggle in the capsule, without search', (tester) async {
    await open(tester, 1);

    await tester.tap(find.bySemanticsLabel('Show raw terminal'));
    await tester.pumpAndSettle();

    final capsule = find.byKey(TerminalChatHeader.capsuleKey);
    expect(find.descendant(of: capsule, matching: find.text('Idle')), findsOneWidget);
    expect(find.byTooltip('Find in blocks'), findsNothing);
    expect(find.descendant(of: capsule, matching: find.bySemanticsLabel('Show blocks')), findsOneWidget);
  });

  testWidgets('the pill turns to the working colour and elapsed time while the agent works', (tester) async {
    await open(tester, 1);

    harness.commandCubit.onActivity('active');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final capsule = find.byKey(TerminalChatHeader.capsuleKey);
    expect(find.descendant(of: capsule, matching: find.text('Idle')), findsNothing);
    expect(find.descendant(of: capsule, matching: find.byKey(TerminalChatHeader.activityKey)), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a shell has no capsule', (tester) async {
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalBody());
    await tester.pumpAndSettle();

    expect(find.byKey(TerminalChatHeader.capsuleKey), findsNothing);
    expect(find.byKey(TerminalChatHeader.backKey), findsOneWidget);
  });

  testWidgets('the find bar opens below the header', (tester) async {
    await open(tester, 12);

    await tester.tap(find.byTooltip('Find in blocks'));
    await tester.pumpAndSettle();

    final field = find.byType(BlockFindBar);
    expect(tester.getRect(field).top, greaterThanOrEqualTo(tester.getRect(header()).bottom));
  });
}
