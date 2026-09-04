import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart';

class _MockBlocksCubit extends MockCubit<BlocksState> implements BlocksCubit {}

const _hapticsChannel = MethodChannel('operator/haptics');

SessionBlock _shell(String id, {String command = 'ls', String output = 'ok'}) =>
    SessionBlock(
      id: id,
      firstSeq: 1,
      lastSeq: 1,
      kind: BlockKind.tool,
      status: BlockStatus.ok,
      title: 'Shell',
      body: output,
      truncatedLines: 0,
      redacted: false,
      detail: ShellBlockDetail(command: command, output: output, exitCode: 0),
    );

SessionBlock _prompt(String id, String body) => SessionBlock(
  id: id,
  firstSeq: 1,
  lastSeq: 1,
  kind: BlockKind.prompt,
  status: BlockStatus.ok,
  title: 'Prompt',
  body: body,
  truncatedLines: 0,
  redacted: false,
);

void _stubCubit(_MockBlocksCubit cubit, {List<SessionBlock> blocks = const []}) {
  when(() => cubit.state).thenReturn(const BlocksReadyState(1));
  when(() => cubit.sessionId).thenReturn('s-1');
  when(() => cubit.supported).thenReturn(true);
  when(() => cubit.harness).thenReturn('claude-code');
  when(() => cubit.blocks).thenReturn(blocks);
  when(() => cubit.loading).thenReturn(false);
  when(() => cubit.active).thenReturn(false);
  when(() => cubit.loadingOlder).thenReturn(false);
  when(() => cubit.hasOlder).thenReturn(false);
  when(() => cubit.error).thenReturn(null);
  when(() => cubit.refresh()).thenAnswer((_) async {});
  when(() => cubit.loadOlder()).thenAnswer((_) async {});
}

Future<void> _pump(WidgetTester tester, _MockBlocksCubit cubit) =>
    tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: BlocProvider<BlocksCubit>.value(
                value: cubit,
                child: const SizedBox(
                  width: 400,
                  height: 700,
                  child: BlocksBody(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> notification = <MethodCall>[];
  final List<String> clipboard = <String>[];

  setUp(() {
    notification.clear();
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map;
        clipboard.add(args['text'] as String);
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticsChannel, (call) async {
      notification.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_hapticsChannel, null);
  });

  testWidgets('long-press on a block header enters selection mode', (tester) async {
    final cubit = _MockBlocksCubit();
    _stubCubit(cubit, blocks: [_shell('b-1')]);

    await _pump(tester, cubit);

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

    await tester.longPress(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('long-press on the body still opens the action sheet, not selection mode', (tester) async {
    final cubit = _MockBlocksCubit();
    _stubCubit(cubit, blocks: [_shell('b-1', output: 'hello world')]);

    await _pump(tester, cubit);

    await tester.longPress(find.textContaining('hello world'));
    await tester.pumpAndSettle();

    expect(find.text('Copy block'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('tapping a block in selection mode toggles its selected state', (tester) async {
    final cubit = _MockBlocksCubit();
    _stubCubit(
      cubit,
      blocks: [_shell('b-1', output: 'one'), _shell('b-2', output: 'two')],
    );

    await _pump(tester, cubit);

    await tester.longPress(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

    await tester.tap(find.textContaining('two'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

    await tester.tap(find.textContaining('one'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets(
    'copy writes the selected blocks in document order for an out-of-order selection',
    (tester) async {
      final cubit = _MockBlocksCubit();
      _stubCubit(
        cubit,
        blocks: [
          _prompt('p-1', 'first prompt'),
          _shell('s-1', output: 'shell output'),
          _prompt('p-2', 'last prompt'),
        ],
      );

      await _pump(tester, cubit);

      final promptHeaders = find.text('Prompt');
      await tester.longPress(promptHeaders.last);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.textContaining('first prompt'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.textContaining('shell output'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('block-selection-copy')));
      await tester.pumpAndSettle();

      expect(clipboard, hasLength(1));
      final text = clipboard.single;
      final firstIdx = text.indexOf('first prompt');
      final shellIdx = text.indexOf('shell output');
      final lastIdx = text.indexOf('last prompt');
      expect(firstIdx, isNonNegative);
      expect(shellIdx, isNonNegative);
      expect(lastIdx, isNonNegative);
      expect(firstIdx, lessThan(shellIdx));
      expect(shellIdx, lessThan(lastIdx));
      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('3 selected'), findsNothing);
    },
  );

  testWidgets('cancel exits selection mode without copying', (tester) async {
    final cubit = _MockBlocksCubit();
    _stubCubit(cubit, blocks: [_shell('b-1')]);

    await _pump(tester, cubit);

    await tester.longPress(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsNothing);
    expect(clipboard, isEmpty);
  });

  testWidgets('PopScope blocks the system pop while in selection mode', (tester) async {
    final cubit = _MockBlocksCubit();
    _stubCubit(cubit, blocks: [_shell('b-1')]);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: BlocProvider<BlocksCubit>.value(
                            value: cubit,
                            child: const SizedBox(
                              width: 400,
                              height: 700,
                              child: BlocksBody(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('push'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.byType(BlocksBody), findsOneWidget);

    await tester.longPress(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    final navState = navKey.currentState!;
    expect(navState.canPop(), isTrue);

    await navState.maybePop();
    await tester.pumpAndSettle();

    expect(find.byType(BlocksBody), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets(
    'resets selection state when the session id changes',
    (tester) async {
      final cubit = _MockBlocksCubit();
      _stubCubit(
        cubit,
        blocks: [
          _prompt('p-1', 'first'),
          _shell('s-1', output: 'second'),
        ],
      );

      await _pump(tester, cubit);

      await tester.longPress(find.text('Prompt').first);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      final cubitB = _MockBlocksCubit();
      _stubCubit(
        cubitB,
        blocks: [_prompt('p-1', 'first')],
      );
      when(() => cubitB.sessionId).thenReturn('s-2');

      await _pump(tester, cubitB);
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    },
  );
}
