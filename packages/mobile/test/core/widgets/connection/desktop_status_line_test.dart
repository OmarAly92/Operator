import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/widgets/connection/desktop_status_line.dart';

import '../../../helpers/connection_harness.dart';

void main() {
  late ConnectionHarness harness;
  final now = DateTime.utc(2026, 9, 25, 12);

  setUp(() => harness = ConnectionHarness(clock: () => now));
  tearDown(() => harness.dispose());

  Future<void> pump(WidgetTester tester, {VoidCallback? onTap, VoidCallback? onRePair, DateTime? fetchedAt}) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<ConnectionCubit>.value(
                value: harness.cubit,
                child: Center(
                  child: DesktopStatusLine(
                    fetchedAt: fetchedAt,
                    onTap: onTap ?? () {},
                    onRePair: onRePair,
                    clock: () => now,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('names the desktop beside its status', (tester) async {
    harness.report(ConnectionOutcome.online, at: now);
    await pump(tester);

    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);
  });

  testWidgets('offline reads in the warning hue, with the cached board time on a cold start', (tester) async {
    harness.report(ConnectionOutcome.unreachable, at: now);
    await pump(tester, fetchedAt: now.subtract(const Duration(minutes: 5)));

    final text = tester.widget<Text>(find.text('Offline · last seen 5m ago'));
    expect(text.style?.color, const DarkSkin().amber);
  });

  testWidgets('tapping opens the desktop list', (tester) async {
    var taps = 0;
    harness.report(ConnectionOutcome.online, at: now);
    await pump(tester, onTap: () => taps++);

    await tester.tap(find.byKey(DesktopStatusLine.tapKey));

    expect(taps, 1);
  });

  testWidgets('after an auth failure the line reads Needs re-pairing and tapping re-pairs', (tester) async {
    var taps = 0;
    var rePairs = 0;
    harness.report(ConnectionOutcome.auth, at: now);
    await pump(tester, onTap: () => taps++, onRePair: () => rePairs++);

    expect(find.text('Needs re-pairing'), findsOneWidget);
    await tester.tap(find.byKey(DesktopStatusLine.tapKey));

    expect(rePairs, 1);
    expect(taps, 0);
  });
}
