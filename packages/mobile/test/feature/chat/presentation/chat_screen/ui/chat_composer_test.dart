import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePicker implements AttachmentPicker {
  _FakePicker({this.images = const []});

  final List<PickedAttachment> images;

  @override
  Future<List<PickedAttachment>> pickImages() async => images;

  @override
  Future<List<PickedAttachment>> pickTextFiles() async => const [];
}

class _InertVoiceProvider implements VoiceProvider {
  @override
  bool get available => false;

  @override
  String? get language => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start(
    VoiceCallbacks callbacks, {
    VoiceMode mode = VoiceMode.push,
  }) async {}

  @override
  void stop() {}

  @override
  void abort() {}
}

PickedAttachment imageAttachment(String id, int bytes) => PickedAttachment(
  id: id,
  name: '$id.png',
  bytes: bytes,
  image: const ChatImageModel(mimeType: 'image/png', data: 'AA=='),
);

ConversationSnapshotModel snapshot({
  List<String> capabilities = const [],
  String controllerState = 'ready',
  List<ConversationTurnModel> turns = const [],
}) => ConversationSnapshotModel(
  conversationId: 'c-1',
  sessionId: 'w-1',
  harness: 'codex',
  controllerState: controllerState,
  latestSequence: 1,
  turns: turns,
  capabilities: capabilities,
);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    if (!sl.isRegistered<VoiceInputCubit>()) {
      sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
        (onTranscript, _) =>
            VoiceInputCubit(_InertVoiceProvider(), onTranscript: onTranscript),
      );
    }
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required ConversationSnapshotModel value,
    AttachmentPicker? picker,
    List<ChatSkillModel> skills = const [],
    List<String> filePaths = const [],
    bool steerUnavailable = false,
    Future<void> Function(
      String, {
      List<ChatImageModel>? attachments,
      List<ChatResourceModel>? resources,
    })?
    onSend,
    Future<void> Function(String)? onSteer,
    VoidCallback? onInterrupt,
  }) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                sessionId: 'w-1',
                snapshot: value,
                skills: skills,
                filePaths: filePaths,
                filePathsTruncated: false,
                configOptions: const [],
                steerUnavailable: steerUnavailable,
                picker: picker ?? _FakePicker(),
                onSend: onSend ?? (text, {attachments, resources}) async {},
                onSteer: onSteer ?? (text) async {},
                onInterrupt: onInterrupt ?? () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends the trimmed message and clears the field', (tester) async {
    String? sent;
    await pumpComposer(
      tester,
      value: snapshot(),
      onSend: (text, {attachments, resources}) async => sent = text,
    );

    await tester.enterText(find.byType(TextField), '  ship it  ');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sent, 'ship it');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('refuses to send an empty message', (tester) async {
    var sends = 0;
    await pumpComposer(
      tester,
      value: snapshot(),
      onSend: (text, {attachments, resources}) async => sends++,
    );

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(sends, 0);
  });

  testWidgets(
    'offers steering only while a turn runs and the provider allows it',
    (tester) async {
      await pumpComposer(
        tester,
        value: snapshot(capabilities: const ['steer']),
      );
      expect(find.text('Steer this turn'), findsNothing);

      await pumpComposer(
        tester,
        value: snapshot(
          capabilities: const ['steer'],
          turns: const [
            ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
          ],
        ),
      );
      expect(find.text('Steer this turn'), findsOneWidget);
      expect(find.text('Queue for next'), findsOneWidget);
    },
  );

  testWidgets('routes a steered message to onSteer instead of onSend', (
    tester,
  ) async {
    String? steered;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [
          ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
        ],
      ),
      onSteer: (text) async => steered = text,
    );

    await tester.enterText(find.byType(TextField), 'use the other file');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.reply));
    await tester.pumpAndSettle();

    expect(steered, 'use the other file');
  });

  testWidgets('offers to stop a running turn when the field is empty', (
    tester,
  ) async {
    var interrupts = 0;
    await pumpComposer(
      tester,
      value: snapshot(
        turns: const [
          ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
        ],
      ),
      onInterrupt: () => interrupts++,
    );

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(interrupts, 1);
  });

  testWidgets('attaches an image and forces the message into a new turn', (
    tester,
  ) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [
          ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
        ],
      ),
      picker: _FakePicker(
        images: const [
          PickedAttachment(
            id: 'a',
            name: 'shot.png',
            bytes: 12,
            image: ChatImageModel(mimeType: 'image/png', data: 'AAA'),
          ),
        ],
      ),
      onSend: (text, {attachments, resources}) async =>
          sentImages = attachments,
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    expect(find.text('shot.png'), findsOneWidget);
    expect(find.textContaining('Attachments start a new turn'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'look at this');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentImages, hasLength(1));
  });

  testWidgets('sends an attachment-only message while a turn is running', (
    tester,
  ) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [
          ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
        ],
      ),
      picker: _FakePicker(images: [imageAttachment('shot', 12)]),
      onSend: (text, {attachments, resources}) async =>
          sentImages = attachments,
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentImages, hasLength(1));
  });

  testWidgets('queues normally when the daemon has refused steering', (
    tester,
  ) async {
    String? sent;
    String? steered;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [
          ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a'),
        ],
      ),
      steerUnavailable: true,
      onSend: (text, {attachments, resources}) async => sent = text,
      onSteer: (text) async => steered = text,
    );

    expect(find.text('Steer this turn'), findsNothing);
    await tester.enterText(find.byType(TextField), 'queue this');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sent, 'queue this');
    expect(steered, isNull);
  });

  testWidgets('accepts only the first eight attachments', (tester) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(),
      picker: _FakePicker(
        images: List.generate(9, (index) => imageAttachment('image-$index', 1)),
      ),
      onSend: (text, {attachments, resources}) async =>
          sentImages = attachments,
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    expect(find.text('You can attach up to 8 items.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'send accepted images');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentImages, hasLength(8));
  });

  testWidgets('rejects images beyond the 25 MB combined limit', (tester) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(),
      picker: _FakePicker(
        images: [
          imageAttachment('first', 9 * 1024 * 1024),
          imageAttachment('second', 9 * 1024 * 1024),
          imageAttachment('third', 9 * 1024 * 1024),
        ],
      ),
      onSend: (text, {attachments, resources}) async =>
          sentImages = attachments,
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    expect(find.text('Images must total under 25 MB.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'send accepted images');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentImages, hasLength(2));
  });

  testWidgets(
    'derives suggestions from text and caret without reopening after dismissal',
    (tester) async {
      await pumpComposer(
        tester,
        value: snapshot(),
        skills: const [ChatSkillModel(name: 'codex', displayName: 'Codex')],
      );

      final composerField = tester.widget<TextField>(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '/cod tail');
      composerField.controller!.selection = const TextSelection.collapsed(
        offset: 4,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Codex'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Codex'), findsNothing);
    },
  );

  testWidgets(
    'offers a text-file attachment only when the provider embeds context',
    (tester) async {
      await pumpComposer(tester, value: snapshot());
      expect(find.byIcon(Icons.note_add_outlined), findsNothing);

      await pumpComposer(
        tester,
        value: snapshot(capabilities: const ['embedded_context']),
      );
      expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
    },
  );

  testWidgets('disables the composer while the controller is stopped', (
    tester,
  ) async {
    await pumpComposer(tester, value: snapshot(controllerState: 'stopped'));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('restores a draft saved for this session', (tester) async {
    await CacheHelper.save(CacheKeys.chatDraft('w-1'), 'half a thought');
    await pumpComposer(tester, value: snapshot());
    expect(find.text('half a thought'), findsOneWidget);
  });
}
