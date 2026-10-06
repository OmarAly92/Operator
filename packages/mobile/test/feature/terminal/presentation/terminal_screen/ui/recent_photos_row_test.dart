import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/add_context_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/recent_photos_row.dart';

import '../../../fake_recent_photos.dart';
import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;
  late FakeRecentPhotos source;

  setUp(() {
    harness = TerminalHarness()..start(harness: 'claude-code');
    source = FakeRecentPhotos()
      ..photos = [
        RecentPhotoModel(id: '1', thumbnail: Uint8List(4)),
        RecentPhotoModel(id: '2', thumbnail: Uint8List(4)),
      ];
    if (sl.isRegistered<RecentPhotosDataSource>()) sl.unregister<RecentPhotosDataSource>();
    sl.registerSingleton<RecentPhotosDataSource>(source);
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    await harness.pump(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => showAddContextSheet(context), child: const Text('Open'))),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the row expands into a strip and a thumbnail toggles a checked attachment, keeping the sheet open', (tester) async {
    await open(tester);
    expect(find.text('Show recent photos'), findsOneWidget);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RecentPhotosRow.stripKey), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();
    expect(harness.cubit.hasAttachment('photo:1'), isTrue);
    expect(find.descendant(of: find.byKey(const ValueKey('recent-photo-1')), matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    expect(find.text('Add context'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();
    expect(harness.cubit.hasAttachment('photo:1'), isFalse);
  });

  testWidgets('denied access turns the row into Allow photo access, which opens Settings', (tester) async {
    source.access = PhotoAccess.denied;
    await open(tester);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(find.text('Allow photo access'), findsOneWidget);
    expect(find.byKey(RecentPhotosRow.stripKey), findsNothing);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    expect(source.settings, 1);
  });

  testWidgets('access granted in Settings expands the denied row on the next tap', (tester) async {
    source.access = PhotoAccess.denied;
    await open(tester);
    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();

    source.access = PhotoAccess.granted;
    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();

    expect(source.settings, 0);
    expect(find.text('Show recent photos'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-photo-1')), findsOneWidget);
  });

  testWidgets('a second tap while a photo loads is ignored and the tile shows progress', (tester) async {
    source.loadGate = Completer<void>();
    await open(tester);
    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('recent-photo-loading-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pump();

    source.loadGate!.complete();
    await tester.pumpAndSettle();

    expect(source.loads, 1);
    expect(harness.cubit.hasAttachment('photo:1'), isTrue);
    expect(find.byKey(const ValueKey('recent-photo-loading-1')), findsNothing);
  });

  testWidgets('a photo that cannot be loaded says so inside the sheet and in the tray', (tester) async {
    source.loadResult = (_) => null;
    await open(tester);
    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachmentNotice, kRecentPhotoLoadFailed);
    expect(tester.widget<Text>(find.byKey(RecentPhotosRow.noticeKey)).data, kRecentPhotoLoadFailed);
    expect(harness.cubit.hasAttachment('photo:1'), isFalse);
  });

  testWidgets('a photo over the limits is refused inside the sheet and in the tray', (tester) async {
    harness.cubit.addAttachments([
      for (var i = 0; i < AttachmentLimits.maxCount; i++)
        ComposerAttachment(id: 'f$i', name: 'f$i.png', mimeType: 'image/png', bytes: Uint8List(4)),
    ]);
    await open(tester);
    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recent-photo-1')));
    await tester.pumpAndSettle();

    expect(harness.cubit.attachmentNotice, kTooManyFiles);
    expect(tester.widget<Text>(find.byKey(RecentPhotosRow.noticeKey)).data, kTooManyFiles);
  });

  testWidgets('limited access offers Manage', (tester) async {
    source.access = PhotoAccess.limited;
    await open(tester);

    await tester.tap(find.byKey(RecentPhotosRow.rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecentPhotosRow.manageKey));
    await tester.pumpAndSettle();

    expect(source.manages, 1);
  });
}
