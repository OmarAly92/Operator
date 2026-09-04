import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/events/event_stream_status.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_stream_banner.dart';

void main() {
  late StreamController<EventStreamStatus> status;

  setUp(() => status = StreamController<EventStreamStatus>.broadcast());
  tearDown(() => status.close());

  Widget host() => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, child) => MaterialApp(
      home: SkinScope(
        skin: const DarkSkin(),
        child: Scaffold(
          body: ChatStreamBanner(
            status: status.stream,
            initial: EventStreamStatus.connected,
          ),
        ),
      ),
    ),
  );

  testWidgets('shows nothing while connected', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.textContaining('updates'), findsNothing);
  });

  testWidgets('warns while reconnecting', (tester) async {
    await tester.pumpWidget(host());
    status.add(EventStreamStatus.reconnecting);
    await tester.pump();
    expect(find.text('Not receiving updates — reconnecting'), findsOneWidget);
  });

  testWidgets('clears the warning once reconnected', (tester) async {
    await tester.pumpWidget(host());
    status.add(EventStreamStatus.reconnecting);
    await tester.pump();
    status.add(EventStreamStatus.connected);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('updates'), findsNothing);
  });
}
