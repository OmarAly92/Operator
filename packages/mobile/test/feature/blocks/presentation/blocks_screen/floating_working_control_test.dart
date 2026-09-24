import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/motion/shimmer.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/floating_working_control.dart';

class _Host extends StatefulWidget {
  const _Host({required this.working, required this.showLatest, this.since, this.coverage, this.onLatest});

  final bool working;
  final bool showLatest;
  final DateTime? Function()? since;
  final ValueNotifier<double>? coverage;
  final VoidCallback? onLatest;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool working = widget.working;
  late bool showLatest = widget.showLatest;

  void set({bool? working, bool? showLatest}) => setState(() {
    this.working = working ?? this.working;
    this.showLatest = showLatest ?? this.showLatest;
  });

  @override
  Widget build(BuildContext context) => Center(
    child: FloatingWorkingControl(
      working: working,
      showLatest: showLatest,
      since: widget.since,
      coverage: widget.coverage,
      onLatest: widget.onLatest ?? () {},
    ),
  );
}

Future<_HostState> _pump(
  WidgetTester tester, {
  bool working = false,
  bool showLatest = false,
  DateTime? Function()? since,
  ValueNotifier<double>? coverage,
  VoidCallback? onLatest,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    SkinScope(
      skin: const DarkSkin(),
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
              child: Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 200,
                  child: _Host(
                    working: working,
                    showLatest: showLatest,
                    since: since,
                    coverage: coverage,
                    onLatest: onLatest,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

final Finder _pill = find.byKey(FloatingWorkingControl.pillKey);
final Finder _latest = find.byKey(FloatingWorkingControl.latestKey);

double _centreX(WidgetTester tester, Finder finder) => tester.getCenter(finder).dx;

void main() {
  const centre = 200.0;

  testWidgets('shows nothing while idle and pinned', (tester) async {
    await _pump(tester);

    expect(_pill, findsNothing);
    expect(_latest, findsNothing);
    expect(find.bySemanticsLabel('Jump to latest'), findsNothing);
  });

  testWidgets('the pill appears only while working and reads the elapsed time', (tester) async {
    final host = await _pump(tester, since: () => DateTime.now().subtract(const Duration(seconds: 12)));
    expect(_pill, findsNothing);

    host.set(working: true);
    await tester.pump();
    await tester.pump(AppMotion.control);

    expect(_pill, findsOneWidget);
    expect(find.text('Working 12s'), findsOneWidget);
    expect(_centreX(tester, _pill), moreOrLessEquals(centre, epsilon: 0.5));
    expect(_latest, findsNothing);

    host.set(working: false);
    await tester.pump();
    await tester.pump(AppMotion.control);
    await tester.pump();

    expect(_pill, findsNothing);
  });

  testWidgets('the timer ticks each second', (tester) async {
    var since = DateTime.now().subtract(const Duration(seconds: 9));
    await _pump(tester, working: true, since: () => since);
    expect(find.text('Working 9s'), findsOneWidget);

    since = since.subtract(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Working 10s'), findsOneWidget);
  });

  testWidgets('without a start time the pill reads Working', (tester) async {
    await _pump(tester, working: true);

    expect(find.text('Working'), findsOneWidget);
  });

  testWidgets('the shimmer runs over the label only', (tester) async {
    await _pump(tester, working: true, since: () => DateTime.now());

    final shimmer = find.byType(Shimmer);
    expect(shimmer, findsOneWidget);
    expect(find.descendant(of: shimmer, matching: find.text('Working 0s')), findsOneWidget);
    expect(find.descendant(of: _pill, matching: shimmer), findsOneWidget);
  });

  testWidgets('the chevron appears only when unpinned, alone and centred', (tester) async {
    final host = await _pump(tester);

    host.set(showLatest: true);
    await tester.pump();
    await tester.pump(AppMotion.controlFade);

    expect(_latest, findsOneWidget);
    expect(find.bySemanticsLabel('Jump to latest'), findsOneWidget);
    expect(tester.getSize(_latest), const Size(FloatingWorkingControl.size, FloatingWorkingControl.size));
    expect(_centreX(tester, _latest), moreOrLessEquals(centre, epsilon: 0.5));

    host.set(showLatest: false);
    await tester.pump();
    await tester.pump(AppMotion.controlFade);
    await tester.pump();

    expect(_latest, findsNothing);
  });

  testWidgets('tapping the chevron jumps to latest and fires a selection haptic', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    var taps = 0;
    await _pump(tester, showLatest: true, onLatest: () => taps++);

    await tester.tap(_latest);
    await tester.pump();

    expect(taps, 1);
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate').map((call) => call.arguments),
      contains('HapticFeedbackType.selectionClick'),
    );
  });

  testWidgets('pill and chevron sit side by side, centred as a group', (tester) async {
    await _pump(tester, working: true, showLatest: true, since: () => DateTime.now());

    final pill = tester.getRect(_pill);
    final latest = tester.getRect(_latest);
    expect(latest.left - pill.right, moreOrLessEquals(FloatingWorkingControl.gap, epsilon: 0.5));
    expect((pill.left + latest.right) / 2, moreOrLessEquals(centre, epsilon: 0.5));
    expect(latest.center.dy, moreOrLessEquals(pill.center.dy, epsilon: 0.5));
  });

  testWidgets('the chevron slides out beside the pill and the pill slides back to centre', (tester) async {
    final host = await _pump(tester, working: true, since: () => DateTime.now());
    final pillAlone = _centreX(tester, _pill);
    expect(pillAlone, moreOrLessEquals(centre, epsilon: 0.5));

    host.set(showLatest: true);
    await tester.pump();
    await tester.pump(AppMotion.control ~/ 2);
    final pillMid = _centreX(tester, _pill);
    final latestMid = _centreX(tester, _latest);

    await tester.pump(AppMotion.control ~/ 2);
    await tester.pump();
    final pillEnd = _centreX(tester, _pill);
    final latestEnd = _centreX(tester, _latest);

    expect(pillEnd, lessThan(pillAlone - 10));
    expect(pillMid, lessThan(pillAlone - 1));
    expect(pillMid, greaterThan(pillEnd + 1));
    expect(latestMid, lessThan(latestEnd - 0.1));

    host.set(showLatest: false);
    await tester.pump();
    await tester.pump(AppMotion.control ~/ 2);
    final pillBack = _centreX(tester, _pill);
    expect(pillBack, greaterThan(pillEnd + 1));
    expect(pillBack, lessThan(centre - 1));

    await tester.pump(AppMotion.control ~/ 2);
    await tester.pump();
    expect(_centreX(tester, _pill), moreOrLessEquals(centre, epsilon: 0.5));
    expect(_latest, findsNothing);
  });

  testWidgets('the pill width animates to its label', (tester) async {
    DateTime? since;
    await _pump(tester, working: true, since: () => since);
    final narrow = tester.getSize(_pill).width;

    since = DateTime.now().subtract(const Duration(minutes: 42, seconds: 17));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(AppMotion.control ~/ 2);
    final mid = tester.getSize(_pill).width;
    await tester.pump(AppMotion.control);
    final wide = tester.getSize(_pill).width;

    expect(wide, greaterThan(narrow + 10));
    expect(mid, greaterThan(narrow + 1));
    expect(mid, lessThan(wide - 1));
  });

  testWidgets('coverage follows the pill so the list can clear it', (tester) async {
    final coverage = ValueNotifier<double>(0);
    addTearDown(coverage.dispose);
    final host = await _pump(tester, coverage: coverage, since: () => DateTime.now());
    expect(coverage.value, 0);

    host.set(working: true);
    await tester.pump();
    await tester.pump(AppMotion.control ~/ 2);
    expect(coverage.value, greaterThan(0));
    expect(coverage.value, lessThan(FloatingWorkingControl.coverageHeight));

    await tester.pump(AppMotion.control);
    expect(coverage.value, FloatingWorkingControl.coverageHeight);

    host.set(showLatest: true);
    await tester.pump();
    await tester.pump(AppMotion.control);
    expect(coverage.value, FloatingWorkingControl.coverageHeight);

    host.set(working: false);
    await tester.pump();
    await tester.pump(AppMotion.control);
    expect(coverage.value, 0);
  });

  testWidgets('reduce motion changes instantly and runs no shimmer ticker', (tester) async {
    final host = await _pump(tester, reduceMotion: true, since: () => DateTime.now());

    host.set(working: true, showLatest: true);
    await tester.pump();

    final pill = tester.getRect(_pill);
    final latest = tester.getRect(_latest);
    expect((pill.left + latest.right) / 2, moreOrLessEquals(centre, epsilon: 0.5));
    expect(find.byType(ShaderMask), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    host.set(showLatest: false);
    await tester.pump();

    expect(_latest, findsNothing);
    expect(_centreX(tester, _pill), moreOrLessEquals(centre, epsilon: 0.5));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });
}
