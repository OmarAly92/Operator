import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_identity_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart';

class _MockDesktops extends Mock implements DesktopsRepository {}

class _MockRemote extends Mock implements PairingRemoteDataSource {}

class _MockStore extends Mock implements ServerConfigStore {}

const _mac = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);
const _imac = DesktopModel(id: 'b', name: 'iMac', host: '10.0.0.6', port: '3011', secure: false, isActive: false);

void main() {
  late _MockDesktops desktops;
  late _MockRemote remote;
  late _MockStore store;

  setUpAll(() => registerFallbackValue(const ServerConfig(host: '', httpPort: '', secure: false, password: '')));

  setUp(() async {
    desktops = _MockDesktops();
    remote = _MockRemote();
    store = _MockStore();
    when(() => desktops.watchDesktops()).thenAnswer((_) => Stream.value(const [_mac, _imac]));
    when(() => desktops.passwordFor(any())).thenAnswer((_) async => Result.success('pw'));
    when(() => desktops.activate(any(), name: any(named: 'name'))).thenAnswer((_) async => Result.success(null));
    when(() => store.set(any())).thenReturn(null);
    await sl.reset();
    sl.registerFactory<ConnectionsCubit>(() => ConnectionsCubit(desktops, remote, store));
  });

  tearDown(() => sl.reset());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}')),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(onPressed: () => showDesktopSwitcherSheet(context), child: const Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every desktop with the active one marked, and ways to add or manage', (tester) async {
    await open(tester);

    expect(find.text('Desktops'), findsOneWidget);
    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('iMac'), findsOneWidget);
    expect(find.byKey(const Key('switcher-active-a')), findsOneWidget);
    expect(find.byKey(DesktopSwitcherList.pairKey), findsOneWidget);
    expect(find.byKey(DesktopSwitcherList.manageKey), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('tapping another desktop switches to it and closes the sheet', (tester) async {
    when(() => remote.identify(any())).thenAnswer((_) async => const DesktopIdentityModel(name: 'iMac'));
    await open(tester);

    await tester.tap(find.text('iMac'));
    await tester.pumpAndSettle();

    final config = verify(() => store.set(captureAny())).captured.single as ServerConfig;
    expect(config.desktopId, 'b');
    expect(find.text('Desktops'), findsNothing);
  });

  testWidgets('switching desktops tears down every route above the home shell', (tester) async {
    when(() => remote.identify(any())).thenAnswer((_) async => const DesktopIdentityModel(name: 'iMac'));
    await open(tester);
    await tester.tap(find.byKey(DesktopSwitcherList.manageKey));
    await tester.pumpAndSettle();
    expect(find.text('route /connections'), findsOneWidget);

    showDesktopSwitcherSheet(tester.element(find.text('route /connections')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('iMac'));
    await tester.pumpAndSettle();

    expect(find.text('Desktops'), findsNothing);
    expect(find.text('route /connections'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
  });

  testWidgets('a desktop that rejects its password stays listed with the reason and a way to scan again', (tester) async {
    when(() => remote.identify(any())).thenThrow(ServerFailure(error: 'x', message: 'no', statusCode: 401));
    await open(tester);

    await tester.tap(find.text('iMac'));
    await tester.pumpAndSettle();

    expect(find.text('Desktops'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    verifyNever(() => store.set(any()));
  });

  testWidgets('tapping the active desktop just closes the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.text('Mac'));
    await tester.pumpAndSettle();

    expect(find.text('Desktops'), findsNothing);
    verifyNever(() => remote.identify(any()));
  });

  testWidgets('Pair another desktop and Manage desktops lead to their screens', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(DesktopSwitcherList.manageKey));
    await tester.pumpAndSettle();
    expect(find.text('route /connections'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DesktopSwitcherList.pairKey));
    await tester.pumpAndSettle();
    expect(find.text('route /onboarding'), findsOneWidget);
  });
}
