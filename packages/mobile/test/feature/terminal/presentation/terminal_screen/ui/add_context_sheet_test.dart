import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';

import '../../../fake_recent_photos.dart';
import '../../../terminal_harness.dart';

class FakeAttachmentPicker implements AttachmentPicker {
  List<ComposerAttachment> next = const [];
  String? notice;
  Object? error;
  int? lastLimit;

  Future<PickedAttachments> _answer() async {
    final failure = error;
    if (failure != null) throw failure;
    return PickedAttachments(next, notice: notice);
  }

  @override
  Future<PickedAttachments> camera() => _answer();

  @override
  Future<PickedAttachments> photos({required int limit}) {
    lastLimit = limit;
    return _answer();
  }

  @override
  Future<PickedAttachments> files() => _answer();
}

ComposerAttachment png(String id) =>
    ComposerAttachment(id: id, name: '$id.png', mimeType: 'image/png', bytes: Uint8List(4));

void main() {
  late TerminalHarness harness;
  late FakeAttachmentPicker picker;

  setUp(() {
    harness = TerminalHarness()..start(harness: 'claude-code');
    picker = FakeAttachmentPicker();
    if (sl.isRegistered<AttachmentPicker>()) sl.unregister<AttachmentPicker>();
    sl.registerSingleton<AttachmentPicker>(picker);
    if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>();
    sl.registerSingleton<RecentPhotosDataSource>(FakeRecentPhotos());
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    await harness.pump(
      tester,
      Builder(
        builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open')),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet is titled Add context, has a close button and three tiles', (tester) async {
    await open(tester);

    expect(find.text('Add context'), findsOneWidget);
    expect(find.byKey(AppSheet.closeKey), findsOneWidget);
    expect(find.byKey(AddContextBody.cameraKey), findsOneWidget);
    expect(find.byKey(AddContextBody.photosKey), findsOneWidget);
    expect(find.byKey(AddContextBody.filesKey), findsOneWidget);
    expect(find.text('Connectors'), findsNothing);
  });

  testWidgets('picking photos adds them to the composer and closes the sheet', (tester) async {
    picker.next = [png('a'), png('b')];
    harness.cubit.addAttachments([png('existing')]);
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.photosKey));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, AttachmentLimits.maxCount - 1);
    expect(harness.cubit.attachments.map((a) => a.id), ['existing', 'a', 'b']);
    expect(find.text('Add context'), findsNothing);
  });

  testWidgets('a cancelled pick leaves the sheet open', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.filesKey));
    await tester.pumpAndSettle();

    expect(find.text('Add context'), findsOneWidget);
    expect(harness.cubit.attachments, isEmpty);
  });

  testWidgets('a denied camera explains itself in the composer and closes', (tester) async {
    picker.error = const AttachmentPickFailure('Camera access is off. Turn it on in Settings to take a photo.');
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.cameraKey));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachmentNotice, startsWith('Camera access is off'));
    expect(find.text('Add context'), findsNothing);
  });

  testWidgets('an unexpected picker error explains itself in the composer and closes', (tester) async {
    picker.error = StateError('file vanished');
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.filesKey));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachmentNotice, kAttachFailed);
    expect(harness.cubit.attachments, isEmpty);
    expect(find.text('Add context'), findsNothing);
  });

  testWidgets('a full tray says so instead of opening a picker', (tester) async {
    harness.cubit.addAttachments([for (var i = 0; i < AttachmentLimits.maxCount; i++) png('f$i')]);
    picker.next = [png('extra')];
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.photosKey));
    await tester.pumpAndSettle();

    expect(picker.lastLimit, isNull);
    expect(harness.cubit.attachmentNotice, kTooManyFiles);
    expect(harness.cubit.attachments, hasLength(AttachmentLimits.maxCount));
  });

  testWidgets('files the picker refused as too large are named alongside the ones it kept', (tester) async {
    picker.next = [png('kept')];
    picker.notice = kFileTooLarge;
    await open(tester);

    await tester.tap(find.byKey(AddContextBody.filesKey));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachments.map((a) => a.id), ['kept']);
    expect(harness.cubit.attachmentNotice, kFileTooLarge);
  });
}
