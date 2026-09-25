import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_model_chip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SessionCommandParams(command: '')));

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpComposer(WidgetTester tester) => harness.pump(tester, const TerminalComposer());

  testWidgets('typing swaps the microphone for send and clearing restores it', (tester) async {
    await pumpComposer(tester);
    expect(find.byType(MicKey), findsOneWidget);
    expect(find.bySemanticsLabel('Send'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pumpAndSettle();
    expect(find.byType(MicKey), findsNothing);
    expect(find.bySemanticsLabel('Send'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(MicKey), findsOneWidget);
  });

  testWidgets('the trailing action cross-fades between mic and send', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.pump(AppMotion.chatActionSwap ~/ 2);
    expect(find.byType(MicKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(MicKey), findsNothing);
  });

  void stubStop() => when(
    () => harness.controlRepository.sendCommand(any(), any()),
  ).thenAnswer((_) async => Result.success(GlobalResponse<SessionCommandResultModel>()));

  testWidgets('while the agent works with an empty field, stop sits beside the mic', (tester) async {
    harness.commandCubit.onActivity('active');
    await pumpComposer(tester);
    await tester.pumpAndSettle();

    expect(find.byType(MicKey), findsOneWidget);
    expect(find.bySemanticsLabel('Stop'), findsOneWidget);
    final stop = tester.getRect(find.bySemanticsLabel('Stop'));
    final mic = tester.getRect(find.byType(MicKey));
    expect(stop.right, lessThanOrEqualTo(mic.left));
    expect(stop.size, const Size.square(ComposerActionButton.size));

    await tester.enterText(find.byType(TextField), 'next step');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Stop'), findsNothing);
    expect(find.bySemanticsLabel('Send'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    harness.commandCubit.onActivity('idle');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Stop'), findsNothing);
    expect(find.byType(MicKey), findsOneWidget);
  });

  testWidgets('stop fades and scales in over the action swap', (tester) async {
    await pumpComposer(tester);
    harness.commandCubit.onActivity('active');
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.chatActionSwap ~/ 2);

    final fades = tester
        .widgetList<FadeTransition>(
          find.descendant(of: find.byType(ComposerStopButton), matching: find.byType(FadeTransition)),
        )
        .toList();
    expect(fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('tapping stop interrupts the turn: it runs stop, never kill, and opens no dialog', (tester) async {
    stubStop();
    harness.commandCubit.onActivity('active');
    await pumpComposer(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Stop'));
    await tester.pumpAndSettle();

    verify(() => harness.controlRepository.sendCommand('s-1', const SessionCommandParams(command: 'stop'))).called(1);
    verifyNever(() => harness.sessionsRepository.kill(any()));
    await tester.pump(const Duration(minutes: 1));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dictation can start while the agent works', (tester) async {
    harness.voice.availableValue = true;
    harness.commandCubit.onActivity('active');
    await pumpComposer(tester);
    await tester.pumpAndSettle();

    final gesture = await tester.press(find.byType(MicKey));
    await tester.pump();
    await tester.pump();

    expect(harness.voice.callbacks, isNotNull);
    expect(find.text('Keep holding…'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the mic is never swapped out from under a live recording', (tester) async {
    harness.voice.availableValue = true;
    await pumpComposer(tester);
    await tester.pumpAndSettle();
    final micElement = tester.element(find.byType(MicKey));

    final gesture = await tester.startGesture(tester.getCenter(find.byType(MicKey)));
    await tester.pump();
    await tester.pump();
    harness.voice.callbacks!.onReady();
    harness.commandCubit.onActivity('active');
    harness.cubit.composer.text = 'typed while recording';
    await tester.pump();
    await tester.pump();
    await tester.pump(AppMotion.chatActionSwap * 2);

    expect(find.byType(MicKey), findsOneWidget);
    expect(tester.element(find.byType(MicKey)), same(micElement));
    expect(find.bySemanticsLabel('Send'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.voice.stops + harness.voice.aborts, 1);
  });

  testWidgets('a shell never offers stop or session actions', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    harness.commandCubit.onActivity('active');
    await pumpComposer(tester);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Stop'), findsNothing);
    expect(find.byType(MicKey), findsOneWidget);
    expect(find.byTooltip('Session actions'), findsNothing);
  });

  testWidgets('the agent composer has no session actions button and its field starts at the shell inset', (tester) async {
    await pumpComposer(tester);
    expect(find.byTooltip('Session actions'), findsNothing);
    expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    final agentInset = tester.getRect(find.byType(TextField)).left - tester.getRect(find.byKey(TerminalComposer.capsuleKey)).left;

    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(TerminalComposer.capsuleKey));
    expect(tester.getRect(find.byType(TextField)).left - card.left, agentInset);
    expect(tester.getRect(find.byType(ComposerModelChip)).left - card.left, agentInset);

    await tester.pumpWidget(const SizedBox());
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await pumpComposer(tester);
    await tester.pumpAndSettle();
    final shellInset = tester.getRect(find.byType(TextField)).left - tester.getRect(find.byKey(TerminalComposer.capsuleKey)).left;
    expect(agentInset, shellInset);
  });

  testWidgets('opening the model picker keeps the card expanded and returns focus when it closes', (tester) async {
    when(
      () => harness.controlRepository.getModels(any()),
    ).thenAnswer((_) async => Result.success(GlobalResponse<List<SessionModelOptionModel>>(data: const [])));
    harness.commandCubit.onActivity('idle');
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pumpAndSettle();
    final grown = tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height;

    await tester.tapAt(tester.getRect(find.byType(ComposerModelChip)).centerRight - const Offset(12, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ModelPickerSheet), findsOneWidget);
    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, grown);
    expect(find.byType(ComposerModelChip), findsOneWidget);

    Navigator.of(tester.element(find.byType(ModelPickerSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ModelPickerSheet), findsNothing);
    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, grown);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      find.ancestor(of: find.byElementPredicate((e) => e == focused), matching: find.byType(TextField)),
      findsOneWidget,
    );
  });

  RenderEditable editable(WidgetTester tester) => tester.renderObject<RenderEditable>(
    find.descendant(
      of: find.byType(EditableText),
      matching: find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Editable'),
    ),
  );

  void expectFieldFullyShown(WidgetTester tester, {required int lines}) {
    final capsule = tester.getRect(find.byKey(TerminalComposer.capsuleKey));
    final field = tester.getRect(find.byType(TextField));
    final render = editable(tester);
    expect(capsule.contains(field.topLeft) && capsule.contains(field.bottomRight - const Offset(0.01, 0.01)), isTrue);
    expect(render.size.height, greaterThanOrEqualTo(render.preferredLineHeight * lines));
    expect(field.height, greaterThanOrEqualTo(render.size.height));
  }

  testWidgets('the hint and its descenders fit the resting capsule, centred', (tester) async {
    await pumpComposer(tester);

    expectFieldFullyShown(tester, lines: 1);
    final hint = tester.renderObject<RenderParagraph>(find.text('Message the agent...'));
    final field = tester.getRect(find.byType(TextField));
    expect(hint.size.height, lessThanOrEqualTo(field.height));
    final painter = TextPainter(
      text: hint.text,
      textScaler: hint.textScaler,
      maxLines: hint.maxLines,
      ellipsis: hint.overflow == TextOverflow.ellipsis ? '\u2026' : null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: hint.size.width);
    expect(painter.height, lessThanOrEqualTo(field.height));
    expect(painter.height, lessThanOrEqualTo(hint.size.height));
    painter.dispose();
    final capsule = tester.getRect(find.byKey(TerminalComposer.capsuleKey));
    expect((field.center.dy - capsule.center.dy).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('typed text in the expanded card is shown in full', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'first line\nsecond line\nthird line');
    await tester.pumpAndSettle();

    expectFieldFullyShown(tester, lines: 3);
  });

  testWidgets('rests as a 48pt glass capsule', (tester) async {
    await pumpComposer(tester);
    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, TerminalComposer.restHeight);
    final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
    expect(glass.kind, GlassShapeKind.capsule);
    expect(glass.variant, GlassVariant.regular);
    expect(glass.size, TerminalComposer.restHeight);
    expect(find.byType(ComposerModelChip), findsNothing);
  });

  testWidgets('a newline grows the capsule into a card with the model chip, and clearing collapses it', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pump();
    await tester.pump(AppMotion.composerMorph ~/ 2);
    final midway = tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height;
    await tester.pumpAndSettle();
    final grown = tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height;

    expect(midway, greaterThan(TerminalComposer.restHeight));
    expect(midway, lessThan(grown));
    expect(find.byType(ComposerModelChip), findsOneWidget);
    final card = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
    expect(card.kind, GlassShapeKind.roundedRect);
    expect(card.radius, TerminalComposer.cardRadius);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, TerminalComposer.restHeight);
    expect(find.byType(ComposerModelChip), findsNothing);
    expect(tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey)).kind, GlassShapeKind.capsule);
  });

  testWidgets('text that wraps to a second line expands the capsule', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), List.filled(12, 'wrapping words').join(' '));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, greaterThan(TerminalComposer.restHeight));
    expect(find.byType(ComposerModelChip), findsOneWidget);
  });

  testWidgets('losing focus collapses the card back to the capsule', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pumpAndSettle();
    expect(find.byType(ComposerModelChip), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(TerminalComposer.capsuleKey)).height, TerminalComposer.restHeight);
    expect(find.byType(ComposerModelChip), findsNothing);
    expect(harness.cubit.composer.text, 'first\nsecond');
  });

  testWidgets('the model chip shows the harness glyph and a default label', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.byType(AgentLogo)), findsOneWidget);
    expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.text('Default')), findsOneWidget);
  });

  testWidgets('shows a remote draft as prefill while the field is empty', (tester) async {
    harness.cubit.draft = 'run the sample task';

    await pumpComposer(tester);

    expect(find.text('run the sample task'), findsOneWidget);
  });

  testWidgets('hides the remote draft once the user has typed something', (tester) async {
    harness.cubit.draft = 'run the sample task';
    harness.cubit.composer.text = 'already typing';

    await pumpComposer(tester);

    expect(find.text('run the sample task'), findsNothing);
  });

  testWidgets('tapping the remote draft fills the field without sending', (tester) async {
    harness.cubit.draft = 'run the sample task';

    await pumpComposer(tester);
    await tester.tap(find.text('run the sample task'));
    await tester.pump();

    expect(harness.cubit.composer.text, 'run the sample task');
    verifyNever(() => harness.mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
  });

  // In the running app fetchDraft() always resolves AFTER the composer's first
  // build, so a hint that reads cubit.draft once at build time never appears.
  testWidgets('a draft that arrives after the first build still shows', (tester) async {
    when(
      () => harness.terminalRepository.getDraft(any()),
    ).thenAnswer((_) async => Result.success('run the sample task'));

    await pumpComposer(tester);
    expect(find.text('run the sample task'), findsNothing);

    await harness.cubit.fetchDraft();
    await tester.pump();
    await tester.pump();

    expect(find.text('run the sample task'), findsOneWidget);
  });

  testWidgets('an empty remote draft shows nothing', (tester) async {
    harness.cubit.draft = '';

    await pumpComposer(tester);

    expect(find.byType(TerminalComposerDraftHint), findsOneWidget);
    expect(find.descendant(of: find.byType(TerminalComposerDraftHint), matching: find.byType(AppText)), findsNothing);
  });
}
