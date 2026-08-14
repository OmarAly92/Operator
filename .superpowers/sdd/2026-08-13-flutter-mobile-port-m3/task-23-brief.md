### Task 23: The composer

**Files:**
- Create: `packages/mobile/lib/feature/chat/logic/attachment_picker.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart`
- Create: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`
- Modify: `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`

**Interfaces:**
- Consumes: the composer suggestion logic (Task 9), `dockInset` (Task 10), `ChatImageModel`/
  `ChatResourceModel` (Task 14), `ConversationSnapshotModel`.
- Produces:
  - `class PickedAttachment extends Equatable` — `id`, `name`, `bytes (int)`, `image`, `resource`
  - `abstract class AttachmentPicker` — `Future<List<PickedAttachment>> pickImages()`,
    `Future<List<PickedAttachment>> pickTextFiles()`, plus
    `class AttachmentPickerException implements Exception`
  - `class PlatformAttachmentPicker implements AttachmentPicker` (image_picker + file_selector)
  - `Future<String?> showSuggestionSheet(BuildContext, {required SuggestionKind kind, required List<ChatSkillModel> skills, required List<String> filePaths, required bool filePathsTruncated})`
  - `class ChatComposer extends StatefulWidget` — `sessionId`, `snapshot`, `skills`, `filePaths`,
    `filePathsTruncated`, `configOptions`, `steerUnavailable`, `pending`, `error`, `onSend`,
    `onSteer`, `onInterrupt`, `onOpenSettings`, `picker`
  - `CacheKeys.chatDraft(String sessionId)`

The picker is an interface with a platform implementation because `image_picker` and
`file_selector` both need a live platform channel: a widget test that touched them directly would
either hang or need a channel mock per test. The composer takes `AttachmentPicker? picker` and
falls back to `PlatformAttachmentPicker()`, so production wiring is unchanged and tests inject a
fake.

The limits and their copy are ported verbatim, because each one is a message a user reads at the
moment something failed: 8 attachments total, 10 MB per image, 25 MB of images combined, 500 KB per
embedded text file (with the "Reference a worktree file with @ instead" advice that tells the user
what to do next).

Two composer behaviors are subtle and load-bearing:

- **Steer is only offered while a turn is running, the provider advertises `steer`, the daemon has
  not already refused it, and there are no attachments.** Attachments start a new turn — an image
  cannot join a turn already in flight — which is why picking one forces the delivery choice to
  "Queue for next".
- **The suggestion trigger is recomputed from text and caret only.** RN's comment records the bug:
  depending on the trigger itself re-runs the effect forever ("Maximum update depth exceeded") and
  reopens a picker the user just dismissed. In Flutter the same trap is a `setState` inside a
  listener that reads the value it writes, so the trigger is derived in `_onTextChanged` and never
  read back as an input.

The mic key is **absent**, not disabled — voice is M5.

- [x] **Step 1: Write the failing test**

`packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePicker implements AttachmentPicker {
  _FakePicker({this.images = const [], this.files = const []});

  final List<PickedAttachment> images;
  final List<PickedAttachment> files;

  @override
  Future<List<PickedAttachment>> pickImages() async => images;

  @override
  Future<List<PickedAttachment>> pickTextFiles() async => files;
}

ConversationSnapshotModel snapshot({
  List<String> capabilities = const [],
  String controllerState = 'ready',
  List<ConversationTurnModel> turns = const [],
}) =>
    ConversationSnapshotModel(
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
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required ConversationSnapshotModel value,
    AttachmentPicker? picker,
    List<ChatSkillModel> skills = const [],
    List<String> filePaths = const [],
    Future<void> Function(String, {List<ChatImageModel>? attachments, List<ChatResourceModel>? resources})? onSend,
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
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
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

  testWidgets('offers steering only while a turn runs and the provider allows it', (tester) async {
    await pumpComposer(tester, value: snapshot(capabilities: const ['steer']));
    expect(find.text('Steer this turn'), findsNothing);

    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
    );
    expect(find.text('Steer this turn'), findsOneWidget);
    expect(find.text('Queue for next'), findsOneWidget);
  });

  testWidgets('routes a steered message to onSteer instead of onSend', (tester) async {
    String? steered;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
      onSteer: (text) async => steered = text,
    );

    await tester.enterText(find.byType(TextField), 'use the other file');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.reply));
    await tester.pumpAndSettle();

    expect(steered, 'use the other file');
  });

  testWidgets('offers to stop a running turn when the field is empty', (tester) async {
    var interrupts = 0;
    await pumpComposer(
      tester,
      value: snapshot(turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')]),
      onInterrupt: () => interrupts++,
    );

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(interrupts, 1);
  });

  testWidgets('attaches an image and forces the message into a new turn', (tester) async {
    List<ChatImageModel>? sentImages;
    await pumpComposer(
      tester,
      value: snapshot(
        capabilities: const ['steer'],
        turns: const [ConversationTurnModel(id: 't1', state: 'running', requestedAt: 'a')],
      ),
      picker: _FakePicker(images: const [
        PickedAttachment(
          id: 'a',
          name: 'shot.png',
          bytes: 12,
          image: ChatImageModel(mimeType: 'image/png', data: 'AAA'),
        ),
      ]),
      onSend: (text, {attachments, resources}) async => sentImages = attachments,
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

  testWidgets('offers a text-file attachment only when the provider embeds context', (tester) async {
    await pumpComposer(tester, value: snapshot());
    expect(find.byIcon(Icons.note_add_outlined), findsNothing);

    await pumpComposer(tester, value: snapshot(capabilities: const ['embedded_context']));
    expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
  });

  testWidgets('disables the composer while the controller is stopped', (tester) async {
    await pumpComposer(tester, value: snapshot(controllerState: 'stopped'));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('restores a draft saved for this session', (tester) async {
    await CacheHelper.save(CacheKeys.chatDraft('w-1'), 'half a thought');
    await pumpComposer(tester, value: snapshot());
    expect(find.text('half a thought'), findsOneWidget);
  });
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`
Expected: FAIL — the composer does not exist.

- [x] **Step 3: Add the draft cache key**

In `packages/mobile/lib/core/helpers/cache/cache_keys.dart`:

```dart
  static String chatDraft(String sessionId) => 'opr.chat.draft.$sessionId';
```

- [x] **Step 4: Write the attachment picker**

`packages/mobile/lib/feature/chat/logic/attachment_picker.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

const int kMaxAttachments = 8;
const int kMaxImageBytes = 10 * 1024 * 1024;
const int kMaxImageBytesTotal = 25 * 1024 * 1024;
const int kMaxEmbeddedFileBytes = 500000;
const Set<String> kSupportedImageTypes = {
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/gif',
  'image/webp',
  'image/bmp',
};

class AttachmentPickerException implements Exception {
  const AttachmentPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedAttachment extends Equatable {
  const PickedAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    this.image,
    this.resource,
  });

  final String id;
  final String name;
  final int bytes;
  final ChatImageModel? image;
  final ChatResourceModel? resource;

  bool get isImage => image != null;

  @override
  List<Object?> get props => [id, name, bytes, image, resource];
}

abstract class AttachmentPicker {
  Future<List<PickedAttachment>> pickImages();
  Future<List<PickedAttachment>> pickTextFiles();
}

class PlatformAttachmentPicker implements AttachmentPicker {
  PlatformAttachmentPicker({ImagePicker? imagePicker}) : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<PickedAttachment>> pickImages() async {
    final assets = await _imagePicker.pickMultiImage(imageQuality: 82, limit: 4);
    final picked = <PickedAttachment>[];

    for (final asset in assets) {
      final mimeType = (asset.mimeType ?? 'image/jpeg').toLowerCase();
      if (!kSupportedImageTypes.contains(mimeType)) {
        throw const AttachmentPickerException(
          'Only PNG, JPEG, GIF, WebP, and BMP images are supported.',
        );
      }
      final bytes = await asset.readAsBytes();
      if (bytes.length > kMaxImageBytes) {
        throw const AttachmentPickerException('Each image must be under 10 MB.');
      }
      picked.add(
        PickedAttachment(
          id: '${asset.path}-${DateTime.now().microsecondsSinceEpoch}',
          name: asset.name.isEmpty ? 'Image' : asset.name,
          bytes: bytes.length,
          image: ChatImageModel(mimeType: mimeType, data: base64Encode(bytes)),
        ),
      );
    }
    return picked;
  }

  @override
  Future<List<PickedAttachment>> pickTextFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'text',
          mimeTypes: ['text/*', 'application/json', 'application/xml', 'application/yaml'],
          uniformTypeIdentifiers: ['public.plain-text', 'public.json', 'public.xml', 'public.source-code'],
        ),
      ],
    );

    final picked = <PickedAttachment>[];
    for (final file in files) {
      final body = await file.readAsString();
      final bytes = utf8.encode(body).length;
      if (bytes > kMaxEmbeddedFileBytes) {
        throw AttachmentPickerException(
          '${file.name} is larger than 500 KB. Reference a worktree file with @ instead.',
        );
      }
      picked.add(
        PickedAttachment(
          id: '${file.path}-${DateTime.now().microsecondsSinceEpoch}',
          name: file.name,
          bytes: bytes,
          resource: ChatResourceModel(
            uri: 'mobile-attachment://${Uri.encodeComponent(file.name)}',
            name: file.name,
            mimeType: file.mimeType ?? 'text/plain',
            text: body,
          ),
        ),
      );
    }
    return picked;
  }
}
```

- [x] **Step 5: Write the suggestion sheet**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

Future<String?> showSuggestionSheet(
  BuildContext context, {
  required SuggestionKind kind,
  required List<ChatSkillModel> skills,
  required List<String> filePaths,
  required bool filePathsTruncated,
  String initialQuery = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.skin.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => _SuggestionSheet(
      kind: kind,
      skills: skills,
      filePaths: filePaths,
      filePathsTruncated: filePathsTruncated,
      initialQuery: initialQuery,
    ),
  );
}

class _SuggestionSheet extends StatefulWidget {
  const _SuggestionSheet({
    required this.kind,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.initialQuery,
  });

  final SuggestionKind kind;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final String initialQuery;

  @override
  State<_SuggestionSheet> createState() => _SuggestionSheetState();
}

class _SuggestionSheetState extends State<_SuggestionSheet> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final choices = widget.kind == SuggestionKind.skills
        ? rankComposerSkills(widget.skills, _query.text)
        : rankComposerFiles(widget.filePaths, _query.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppText(
                      widget.kind == SuggestionKind.skills ? 'Skills' : 'Worktree files',
                      style: AppTextStyle.style17SemiBold,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 19, color: skin.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: AppTextStyle.style14Regular.copyWith(color: skin.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.kind == SuggestionKind.skills ? 'Find a skill' : 'Find a file',
                  hintStyle: AppTextStyle.style14Regular.copyWith(color: skin.textFaint),
                  filled: true,
                  fillColor: skin.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (widget.kind == SuggestionKind.files && widget.filePathsTruncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: AppText(
                  "Showing the daemon's capped path list. Narrow your search or type a path directly.",
                  style: AppTextStyle.style10Regular.copyWith(color: skin.amber),
                  maxLines: 2,
                ),
              ),
            const VerticalSpace(8),
            Expanded(
              child: choices.isEmpty
                  ? Center(
                      child: AppText(
                        'No matches',
                        style: AppTextStyle.style13Regular.copyWith(color: skin.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(choice.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: skin.borderSubtle)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AppText(choice.label, style: AppTextStyle.style13SemiBold),
                                      if (choice.detail != null)
                                        AppText(
                                          choice.detail!,
                                          style: AppTextStyle.style11Regular
                                              .copyWith(color: skin.textTertiary),
                                          maxLines: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                if (choice.badge != null)
                                  AppText(
                                    choice.badge!.toUpperCase(),
                                    style: AppTextStyle.style9Regular.copyWith(color: skin.textFaint),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 6: Write the composer**

`packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';
import 'package:operator_mobile/feature/chat/data/model/chat_catalog_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/attachment_picker.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.sessionId,
    required this.snapshot,
    required this.skills,
    required this.filePaths,
    required this.filePathsTruncated,
    required this.configOptions,
    required this.onSend,
    required this.onSteer,
    required this.onInterrupt,
    required this.onOpenSettings,
    this.steerUnavailable = false,
    this.pending = false,
    this.error,
    this.picker,
  });

  final String sessionId;
  final ConversationSnapshotModel snapshot;
  final List<ChatSkillModel> skills;
  final List<String> filePaths;
  final bool filePathsTruncated;
  final List<ChatConfigOptionModel> configOptions;
  final bool steerUnavailable;
  final bool pending;
  final String? error;
  final AttachmentPicker? picker;
  final Future<void> Function(String text, {List<ChatImageModel>? attachments, List<ChatResourceModel>? resources}) onSend;
  final Future<void> Function(String text) onSteer;
  final VoidCallback onInterrupt;
  final VoidCallback onOpenSettings;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final AttachmentPicker _picker = widget.picker ?? PlatformAttachmentPicker();

  Timer? _draftTimer;
  List<PickedAttachment> _attachments = [];
  ComposerSuggestion? _trigger;
  bool _queueDelivery = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    final draft = CacheHelper.get(CacheKeys.chatDraft(widget.sessionId)) as String?;
    if (draft != null && draft.isNotEmpty) _controller.text = draft;
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _turnRunning => widget.snapshot.turns.any((turn) => turn.state == 'running');

  bool get _canSteer =>
      widget.snapshot.can('steer') && !widget.steerUnavailable && _turnRunning;

  bool get _steerEligible => _canSteer && !_queueDelivery && _attachments.isEmpty;

  bool get _stopped => widget.snapshot.controllerState == 'stopped';

  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), () {
      final text = _controller.text;
      unawaited(text.isEmpty
          ? CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId))
          : CacheHelper.save(CacheKeys.chatDraft(widget.sessionId), text));
    });

    final caret = _controller.selection.baseOffset;
    final suggestion = findComposerSuggestion(_controller.text, caret < 0 ? null : caret);
    final available = suggestion == null
        ? false
        : suggestion.kind == SuggestionKind.skills
            ? widget.skills.isNotEmpty
            : widget.filePaths.isNotEmpty;

    if (available && suggestion != _trigger) {
      _trigger = suggestion;
      unawaited(_openSuggestions(suggestion!.kind, suggestion.query));
    } else if (!available) {
      _trigger = null;
    }
    setState(() {});
  }

  Future<void> _openSuggestions(SuggestionKind kind, String query) async {
    final trigger = _trigger;
    final value = await showSuggestionSheet(
      context,
      kind: kind,
      skills: widget.skills,
      filePaths: widget.filePaths,
      filePathsTruncated: widget.filePathsTruncated,
      initialQuery: query,
    );
    if (!mounted) return;

    _trigger = null;
    if (value == null) return;

    final text = _controller.text;
    final next = trigger != null && trigger.kind == kind
        ? replaceComposerSuggestion(text, trigger, value)
        : '$text${text.isEmpty || text.endsWith(' ') ? '' : ' '}'
            '${kind == SuggestionKind.skills ? '/$value' : (value.contains(' ') ? '"$value"' : value)} ';

    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _pick(Future<List<PickedAttachment>> Function() pick) async {
    setState(() => _localError = null);
    try {
      final picked = await pick();
      if (!mounted || picked.isEmpty) return;

      final accepted = [..._attachments];
      var imageBytes = accepted.where((item) => item.isImage).fold<int>(0, (sum, item) => sum + item.bytes);
      String? problem;

      for (final item in picked) {
        if (accepted.length >= kMaxAttachments) {
          problem = 'You can attach up to $kMaxAttachments items.';
          break;
        }
        if (item.isImage && imageBytes + item.bytes > kMaxImageBytesTotal) {
          problem = 'Images must total under 25 MB.';
          break;
        }
        accepted.add(item);
        if (item.isImage) imageBytes += item.bytes;
      }

      setState(() {
        _attachments = accepted;
        _localError = problem;
        if (accepted.isNotEmpty) _queueDelivery = true;
      });
    } on AttachmentPickerException catch (error) {
      if (mounted) setState(() => _localError = error.message);
    } catch (error) {
      if (mounted) setState(() => _localError = 'Could not read that attachment.');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && _attachments.isEmpty) return;

    setState(() {
      _submitting = true;
      _localError = null;
    });

    try {
      final images = _attachments.where((item) => item.isImage).map((item) => item.image!).toList();
      final resources = _attachments.where((item) => !item.isImage).map((item) => item.resource!).toList();

      if (_steerEligible) {
        await widget.onSteer(trimmed);
      } else {
        await widget.onSend(
          trimmed,
          attachments: images.isEmpty ? null : images,
          resources: resources.isEmpty ? null : resources,
        );
      }

      if (!mounted) return;
      _controller.clear();
      setState(() => _attachments = []);
      unawaited(CacheHelper.remove(CacheKeys.chatDraft(widget.sessionId)));
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) setState(() => _localError = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final hasContent = _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;
    final sendDisabled = _stopped || widget.pending || _submitting || !hasContent;
    final providerModel = widget.configOptions.where(
      (option) => option.category == 'model' || option.id == 'model' || option.id == 'agent',
    ).firstOrNull;
    final providerLabel = providerModel?.type == 'select'
        ? providerModel!.choices
                .where((choice) => choice.value == providerModel.currentValue)
                .map((choice) => choice.name)
                .firstOrNull ??
            providerModel.currentValue
        : null;
    final selectedModel =
        widget.snapshot.modelReroute?.toModel ?? providerLabel ?? widget.snapshot.settings.model;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8 + dockInset(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, __) => const HorizontalSpace(7),
                itemBuilder: (context, index) {
                  final item = _attachments[index];
                  return Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border.all(color: skin.borderSubtle),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.isImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              base64Decode(item.image!.data),
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.image_outlined, size: 14, color: skin.blue),
                            ),
                          )
                        else
                          Icon(Icons.description_outlined, size: 14, color: skin.blue),
                        const HorizontalSpace(6),
                        Flexible(
                          child: AppText(
                            item.name,
                            style: AppTextStyle.style11Regular.copyWith(color: skin.textSecondary),
                          ),
                        ),
                        const HorizontalSpace(6),
                        InkWell(
                          onTap: () => setState(
                            () => _attachments = _attachments.where((other) => other.id != item.id).toList(),
                          ),
                          child: Icon(Icons.close, size: 13, color: skin.textTertiary),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_localError != null || widget.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 3),
              child: AppText(
                _localError ?? widget.error!,
                style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                maxLines: 3,
              ),
            ),
          Opacity(
            opacity: _stopped ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: skin.bgElevated,
                border: Border.all(color: skin.borderDefault),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !_stopped,
                      maxLines: null,
                      maxLength: 40000,
                      style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary, height: 1.4),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        border: InputBorder.none,
                        hintText: _stopped
                            ? 'Agent is stopped'
                            : _turnRunning
                                ? (_steerEligible
                                    ? 'Agent is working — this goes into its running turn'
                                    : 'Agent is working — this sends when it finishes')
                                : widget.skills.isNotEmpty
                                    ? 'Ask the agent…  / for skills, @ for files'
                                    : 'Ask the agent…  @ for files',
                        hintStyle: AppTextStyle.style15Regular.copyWith(color: skin.textFaint),
                      ),
                    ),
                  ),
                  if (_canSteer) _deliveryChoice(context),
                  Row(
                    children: [
                      _iconButton(context, Icons.attach_file, 'Attach image',
                          _stopped ? null : () => _pick(_picker.pickImages)),
                      if (widget.snapshot.can('embedded_context'))
                        _iconButton(context, Icons.note_add_outlined, 'Attach text file',
                            _stopped ? null : () => _pick(_picker.pickTextFiles)),
                      if (widget.skills.isNotEmpty)
                        _iconButton(context, Icons.terminal, 'Skills',
                            _stopped ? null : () => _openSuggestions(SuggestionKind.skills, '')),
                      if (widget.filePaths.isNotEmpty)
                        _iconButton(context, Icons.alternate_email, 'Worktree files',
                            _stopped ? null : () => _openSuggestions(SuggestionKind.files, '')),
                      Flexible(
                        child: InkWell(
                          onTap: widget.onOpenSettings,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.memory, size: 13, color: skin.textTertiary),
                                const HorizontalSpace(5),
                                Flexible(
                                  child: AppText(
                                    selectedModel ?? 'Default',
                                    style: AppTextStyle.style10Regular.copyWith(color: skin.textTertiary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_turnRunning && _controller.text.trim().isEmpty)
                        _roundButton(
                          context,
                          icon: Icons.stop,
                          background: skin.bgSubtle,
                          foreground: skin.textPrimary,
                          onTap: widget.onInterrupt,
                        )
                      else
                        _roundButton(
                          context,
                          icon: _steerEligible ? Icons.reply : Icons.arrow_upward,
                          background: skin.blue,
                          foreground: skin.onAccent,
                          busy: widget.pending || _submitting,
                          onTap: sendDisabled ? null : _submit,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryChoice(BuildContext context) {
    final skin = context.skin;
    final forced = _attachments.isNotEmpty;
    Widget option(String label, bool queue) {
      final selected = forced ? queue : _queueDelivery == queue;
      final disabled = forced && !queue;
      return Opacity(
        opacity: disabled ? 0.35 : 1,
        child: InkWell(
          onTap: disabled ? null : () => setState(() => _queueDelivery = queue),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? skin.bgSubtle : null,
              borderRadius: BorderRadius.circular(7),
            ),
            child: AppText(
              label,
              style: AppTextStyle.style10SemiBold
                  .copyWith(color: selected ? skin.textPrimary : skin.textTertiary),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          option('Steer this turn', false),
          const HorizontalSpace(3),
          option('Queue for next', true),
          if (forced)
            Expanded(
              child: AppText(
                'Attachments start a new turn.',
                style: AppTextStyle.style9Regular.copyWith(color: skin.textFaint),
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton(BuildContext context, IconData icon, String label, VoidCallback? onTap) {
    final skin = context.skin;
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: onTap == null ? skin.textFaint : skin.textTertiary),
    );
  }

  Widget _roundButton(
    BuildContext context, {
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                  )
                : Icon(icon, size: 17, color: foreground),
          ),
        ),
      ),
    );
  }
}
```

`firstOrNull` on the two `where(...)` chains comes from `package:collection`; add
`import 'package:collection/collection.dart';` if the analyzer asks for it.

- [x] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`
Expected: PASS.

- [x] **Step 8: Verify nothing regressed and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 560/560 green.

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): add the chat composer with attachments"
```

---
