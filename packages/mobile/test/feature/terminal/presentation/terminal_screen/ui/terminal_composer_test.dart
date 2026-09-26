import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/blocks/data/model/params/session_command_params.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_command_result_model.dart';
import 'package:operator_mobile/feature/blocks/data/model/session_model_option_model.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/model_picker_sheet.dart';
import 'package:operator_mobile/feature/dictation/ui/mic_key.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/agent_logo.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/stage_session_attachments_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/staged_attachments_model.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_action_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_add_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_attachment_tray.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/composer_model_chip.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer_draft_hint.dart';

import '../../../terminal_harness.dart';

ComposerAttachment png(String id) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(4));

ComposerAttachment pdf(String id) =>
    ComposerAttachment(id: id, name: '$id.pdf', mimeType: 'application/pdf', bytes: Uint8List(4));

void main() {
  late TerminalHarness harness;

  setUpAll(() {
    registerFallbackValue(const SessionCommandParams(command: ''));
    registerFallbackValue(const SendSessionMessageParams(message: ''));
    registerFallbackValue(const StageSessionAttachmentsParams(files: []));
  });

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpComposer(WidgetTester tester) => harness.pump(tester, const TerminalComposer());

  Future<void> useShell() async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
  }

  Rect card(WidgetTester tester) => tester.getRect(find.byKey(TerminalComposer.capsuleKey));

  RenderEditable editable(WidgetTester tester) => tester.renderObject<RenderEditable>(
    find.descendant(
      of: find.byType(EditableText),
      matching: find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Editable'),
    ),
  );

  void expectFieldFullyShown(WidgetTester tester, {required int lines}) {
    final capsule = card(tester);
    final field = tester.getRect(find.byType(TextField));
    final render = editable(tester);
    expect(capsule.contains(field.topLeft) && capsule.contains(field.bottomRight - const Offset(0.01, 0.01)), isTrue);
    expect(render.size.height, greaterThanOrEqualTo(render.preferredLineHeight * lines));
    expect(field.height, greaterThanOrEqualTo(render.size.height));
  }

  void stubStop() => when(
    () => harness.controlRepository.sendCommand(any(), any()),
  ).thenAnswer((_) async => Result.success(GlobalResponse<SessionCommandResultModel>()));

  group('agent composer', () {
    testWidgets('is a two-row glass card: the field on top, + and the model chip below', (tester) async {
      await pumpComposer(tester);

      final box = card(tester);
      final field = tester.getRect(find.byType(TextField));
      final plus = tester.getRect(find.byType(ComposerAddButton));
      final chip = tester.getRect(find.byType(ComposerModelChip));
      final mic = tester.getRect(find.byType(MicKey));
      expect(field.bottom, lessThanOrEqualTo(plus.top));
      expect(plus.left - box.left, 6);
      expect(plus.right, lessThan(chip.left));
      expect(chip.right, lessThan(mic.left));
      expect(box.right - mic.right, 6);
      expect(box.bottom - plus.bottom, 6);
      expect(box.bottom - mic.bottom, 6);

      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.roundedRect);
      expect(glass.radius, TerminalComposer.cardRadius);
      expect(glass.variant, GlassVariant.regular);
      expect(glass.size, TerminalComposer.restHeight);
    });

    testWidgets('the hint fits the resting card', (tester) async {
      await pumpComposer(tester);

      expectFieldFullyShown(tester, lines: 1);
      expect(find.text('Message the agent...'), findsOneWidget);
    });

    testWidgets('typing shows Send after the mic and clearing hides it', (tester) async {
      await pumpComposer(tester);
      expect(find.bySemanticsLabel('Send'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pumpAndSettle();
      expect(find.byType(MicKey), findsOneWidget);
      expect(tester.getRect(find.bySemanticsLabel('Send')).left, greaterThanOrEqualTo(tester.getRect(find.byType(MicKey)).right));

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Send'), findsNothing);
      expect(find.byType(MicKey), findsOneWidget);
    });

    testWidgets('an attachment alone offers Send', (tester) async {
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a')]);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('while the agent works with an empty field, Stop sits after the mic', (tester) async {
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      final stop = tester.getRect(find.bySemanticsLabel('Stop'));
      final mic = tester.getRect(find.byType(MicKey));
      expect(stop.left, greaterThanOrEqualTo(mic.right));
      expect(stop.size, const Size.square(ComposerActionButton.size));

      await tester.enterText(find.byType(TextField), 'next step');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Stop'), findsNothing);
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('stop fades and scales in over the action swap', (tester) async {
      await pumpComposer(tester);
      harness.commandCubit.onActivity('active');
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap ~/ 2);

      final fades = tester
          .widgetList<FadeTransition>(
            find.descendant(of: find.byType(ComposerSendSlot), matching: find.byType(FadeTransition)),
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

    testWidgets('the mic stays the same element while recording, even when Send appears', (tester) async {
      harness.voice.availableValue = true;
      await pumpComposer(tester);
      await tester.pumpAndSettle();
      final micElement = tester.element(find.byType(MicKey));

      final gesture = await tester.startGesture(tester.getCenter(find.byType(MicKey)));
      await tester.pump();
      await tester.pump();
      harness.voice.callbacks!.onReady();
      harness.cubit.composer.text = 'typed while recording';
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap * 2);

      expect(tester.element(find.byType(MicKey)), same(micElement));
      expect(find.bySemanticsLabel('Send'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.voice.stops + harness.voice.aborts, 1);
    });

    testWidgets('tapping + opens Add context', (tester) async {
      await pumpComposer(tester);

      await tester.tap(find.byType(ComposerAddButton));
      await tester.pumpAndSettle();

      expect(find.text('Add context'), findsOneWidget);
    });

    testWidgets('attachments sit in a tray above the field, each with a remove button', (tester) async {
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a'), pdf('b')]);
      await tester.pumpAndSettle();

      final tray = tester.getRect(find.byType(ComposerAttachmentTray));
      expect(tray.bottom, lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
      expect(find.text('b.pdf'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Remove b.pdf'));
      await tester.pumpAndSettle();
      expect(harness.cubit.attachments.map((a) => a.id), ['a']);
    });

    testWidgets('each remove badge answers taps across a 44pt area inside its item', (tester) async {
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a'), pdf('b')]);
      await tester.pumpAndSettle();

      final hit = tester.getRect(find.bySemanticsLabel('Remove b.pdf'));
      expect(hit.width, greaterThanOrEqualTo(44));
      expect(hit.height, greaterThanOrEqualTo(44));
      expect(tester.getRect(find.byType(ComposerAttachmentTray)).contains(hit.topLeft), isTrue);

      await tester.tapAt(hit.bottomLeft + const Offset(2, -2));
      await tester.pumpAndSettle();
      expect(harness.cubit.attachments.map((a) => a.id), ['a']);
    });

    testWidgets('closing Add context returns focus to the field', (tester) async {
      await pumpComposer(tester);

      await tester.tap(find.byType(ComposerAddButton));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Add context'))).pop();
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(of: find.byElementPredicate((e) => e == focused), matching: find.byType(TextField)),
        findsOneWidget,
      );
    });

    testWidgets('the resting card is agentRestHeight tall', (tester) async {
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      expect(card(tester).height, moreOrLessEquals(TerminalComposer.agentRestHeight, epsilon: 0.5));
    });

    testWidgets('a notice shows in the tray and tapping it dismisses it', (tester) async {
      await pumpComposer(tester);
      harness.cubit.showAttachmentNotice('Each file must be under 10 MB.');
      await tester.pumpAndSettle();

      expect(find.byKey(ComposerAttachmentTray.noticeKey), findsOneWidget);
      await tester.tap(find.byKey(ComposerAttachmentTray.noticeKey));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerAttachmentTray), findsNothing);
    });

    testWidgets('while staging, the send slot shows progress and + is disabled', (tester) async {
      final upload = Completer<Result<GlobalResponse<StagedAttachmentsModel>, Failure>>();
      when(() => harness.terminalRepository.stageAttachments(any(), any())).thenAnswer((_) => upload.future);
      when(() => harness.terminalRepository.sendSessionMessage(any(), any())).thenAnswer((_) async => Result.success(true));
      await pumpComposer(tester);
      harness.cubit.addAttachments([png('a')]);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      await tester.pump(AppMotion.chatActionSwap);

      expect(find.byKey(ComposerSendSlot.stagingKey), findsOneWidget);
      expect(tester.widget<ComposerAddButton>(find.byType(ComposerAddButton)).onTap, isNull);

      upload.complete(Result.success(const GlobalResponse(data: StagedAttachmentsModel(paths: ['p']))));
      await tester.pumpAndSettle();
      expect(find.byKey(ComposerSendSlot.stagingKey), findsNothing);
      expect(harness.cubit.attachments, isEmpty);
    });

    testWidgets('the card grows with the text and keeps its shape', (tester) async {
      await pumpComposer(tester);
      final rest = card(tester).height;

      await tester.enterText(find.byType(TextField), 'first line\nsecond line\nthird line');
      await tester.pumpAndSettle();

      expect(card(tester).height, greaterThan(rest));
      expectFieldFullyShown(tester, lines: 3);
      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.roundedRect);
      expect(glass.radius, TerminalComposer.cardRadius);
    });

    testWidgets('opening the model picker keeps the card and returns focus when it closes', (tester) async {
      when(
        () => harness.controlRepository.getModels(any()),
      ).thenAnswer((_) async => Result.success(GlobalResponse<List<SessionModelOptionModel>>(data: const [])));
      harness.commandCubit.onActivity('idle');
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pumpAndSettle();
      final grown = card(tester).height;

      await tester.tapAt(tester.getRect(find.byType(ComposerModelChip)).centerRight - const Offset(12, 0));
      await tester.pumpAndSettle();
      expect(find.byType(ModelPickerSheet), findsOneWidget);

      Navigator.of(tester.element(find.byType(ModelPickerSheet))).pop();
      await tester.pumpAndSettle();
      expect(card(tester).height, grown);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(of: find.byElementPredicate((e) => e == focused), matching: find.byType(TextField)),
        findsOneWidget,
      );
    });

    testWidgets('the model chip shows the harness glyph and a default label at rest', (tester) async {
      await pumpComposer(tester);

      expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.byType(AgentLogo)), findsOneWidget);
      expect(find.descendant(of: find.byType(ComposerModelChip), matching: find.text('Default')), findsOneWidget);
    });

    testWidgets('has no session actions button and its field starts at the shell inset', (tester) async {
      await pumpComposer(tester);
      expect(find.byTooltip('Session actions'), findsNothing);
      final agentInset = tester.getRect(find.byType(TextField)).left - card(tester).left;

      await tester.pumpWidget(const SizedBox());
      await useShell();
      await pumpComposer(tester);
      await tester.pumpAndSettle();
      final shellInset = tester.getRect(find.byType(TextField)).left - card(tester).left;
      expect(agentInset, shellInset);
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
  });

  group('send slot', () {
    Widget slot(ComposerTrailing trailing) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Center(child: ComposerSendSlot(trailing: trailing, staging: false, onSend: () {}, onStop: () {})),
    );

    testWidgets('swaps without a transition when animations are disabled', (tester) async {
      await harness.pump(tester, slot(ComposerTrailing.stop));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Stop'), findsOneWidget);

      await harness.pump(tester, slot(ComposerTrailing.send));

      expect(find.bySemanticsLabel('Stop'), findsNothing);
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(of: find.byType(ComposerSendSlot), matching: find.byType(FadeTransition)),
      );
      expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
    });
  });

  group('shell composer', () {
    setUp(useShell);

    testWidgets('rests as a 48pt glass capsule with no + and no model chip', (tester) async {
      await pumpComposer(tester);

      expect(card(tester).height, TerminalComposer.restHeight);
      final glass = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(glass.kind, GlassShapeKind.capsule);
      expect(glass.variant, GlassVariant.regular);
      expect(glass.size, TerminalComposer.restHeight);
      expect(find.byType(ComposerAddButton), findsNothing);
      expect(find.byType(ComposerModelChip), findsNothing);
    });

    testWidgets('typing swaps the microphone for send and clearing restores it', (tester) async {
      await pumpComposer(tester);
      expect(find.byType(MicKey), findsOneWidget);
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

    testWidgets('never offers stop', (tester) async {
      harness.commandCubit.onActivity('active');
      await pumpComposer(tester);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Stop'), findsNothing);
      expect(find.byType(MicKey), findsOneWidget);
    });

    testWidgets('the hint and its descenders fit the resting capsule, centred', (tester) async {
      await pumpComposer(tester);

      expectFieldFullyShown(tester, lines: 1);
      final hint = tester.renderObject<RenderParagraph>(find.text('Send to terminal...'));
      final field = tester.getRect(find.byType(TextField));
      expect(hint.size.height, lessThanOrEqualTo(field.height));
      expect((field.center.dy - card(tester).center.dy).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('a newline grows the capsule into a card, and clearing collapses it', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pump();
      await tester.pump(AppMotion.composerMorph ~/ 2);
      final midway = card(tester).height;
      await tester.pumpAndSettle();
      final grown = card(tester).height;

      expect(midway, greaterThan(TerminalComposer.restHeight));
      expect(midway, lessThan(grown));
      final expanded = tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey));
      expect(expanded.kind, GlassShapeKind.roundedRect);
      expect(expanded.radius, TerminalComposer.cardRadius);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(card(tester).height, TerminalComposer.restHeight);
      expect(tester.widget<GlassSurface>(find.byKey(TerminalComposer.capsuleKey)).kind, GlassShapeKind.capsule);
    });

    testWidgets('text that wraps to a second line expands the capsule', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), List.filled(12, 'wrapping words').join(' '));
      await tester.pumpAndSettle();

      expect(card(tester).height, greaterThan(TerminalComposer.restHeight));
    });

    testWidgets('losing focus collapses the card back to the capsule', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first\nsecond');
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(card(tester).height, TerminalComposer.restHeight);
      expect(harness.cubit.composer.text, 'first\nsecond');
    });
  });
}
