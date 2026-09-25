import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/connection/connection_backoff.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/preferences/app_preferences.dart';
import 'package:operator_mobile/core/replica/replicated.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/connection/desktop_status_line.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/desktop_switcher/ui/desktop_switcher_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart';
import 'package:operator_mobile/feature/sessions/data/model/board_snapshot.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/session_card.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/settings_screen.dart';

import '../../helpers/connection_harness.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockNotificationRepository extends Mock implements NotificationRepository {}

class _MockDesktopsRepository extends Mock implements DesktopsRepository {}

class _MockPairingRepository extends Mock implements PairingRepository {}

class _MockPairingRemoteDataSource extends Mock implements PairingRemoteDataSource {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _MockNotificationRepository notificationRepository;
  ConnectionHarness? harness;
  ConnectionHarness connection() => harness ??= ConnectionHarness();

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
  });

  setUp(() async {
    HomeShell.selectedTab.value = 0;
    AppPreferences.debugLoad(const {});
    repository = _MockSessionsRepository();
    when(() => repository.cachedBoard()).thenAnswer((_) async => null);
    mux = _MockMuxClient();
    notificationRepository = _MockNotificationRepository();
    when(() => mux.sessionPatches).thenAnswer((_) => const Stream<List<SessionPatch>>.empty());
    when(() => mux.boardChanges).thenAnswer((_) => const Stream<void>.empty());
    when(() => mux.status).thenAnswer((_) => const Stream<MuxStatus>.empty());
    when(() => mux.boardStreamReady).thenReturn(false);
    when(() => mux.connect()).thenReturn(null);
    when(() => mux.subscribeSessions()).thenReturn(null);
    when(() => repository.getBoard())
        .thenAnswer((_) async => Result.success(GlobalResponse(data: const BoardSnapshot())));
    when(() => notificationRepository.getNotifications(any())).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(data: const NotificationPageModel(notifications: [], unreadCount: 0)),
      ),
    );
    when(() => notificationRepository.cachedFirstPage()).thenAnswer((_) async => null);
    when(() => notificationRepository.getPhoneAlerts()).thenAnswer(
      (_) async => Result.success(const PhoneAlertStatusModel(enabled: false, claimed: false)),
    );
    await sl.reset();
    sl.registerFactory<PullRequestCubit>(() => PullRequestCubit(_MockPullRequestRepository()));
    final serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(null);
    when(() => serverConfigStore.changes).thenAnswer((_) => const Stream.empty());
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
    final switcherDesktops = _MockDesktopsRepository();
    when(() => switcherDesktops.watchDesktops()).thenAnswer((_) => Stream.value(const []));
    sl.registerFactory<ConnectionsCubit>(
      () => ConnectionsCubit(switcherDesktops, _MockPairingRemoteDataSource(), serverConfigStore),
    );
    final desktopsRepository = _MockDesktopsRepository();
    when(() => desktopsRepository.deactivate()).thenAnswer((_) async => Result.success(null));
    sl.registerFactory<SettingsCubit>(() => SettingsCubit(repository, serverConfigStore, desktopsRepository));
    sl.registerFactory<PhoneAlertsCubit>(
      () => PhoneAlertsCubit(
        notificationRepository,
        launch: (_) async => true,
        copy: (_) async {},
        ntfyDeepLink: false,
      ),
    );
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await sl.reset();
  });

  // A board full of `working` sessions renders a perpetually-breathing
  // `StatusDot` on each card (`docs/design/components.md`'s testing note) —
  // `pumpAndSettle` never terminates while one is mounted, so every pump here
  // is bounded instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder tabLabel(String label) =>
      find.descendant(of: find.byType(GlassTabBar), matching: find.text(label));

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            onGenerateRoute: (settings) =>
                MaterialPageRoute<void>(builder: (_) => Text('route ${settings.name}'), settings: settings),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<ConnectionCubit>.value(value: connection().cubit),
                BlocProvider<SessionsCubit>(create: (_) => SessionsCubit(repository, mux, sl<ServerConfigStore>())),
                BlocProvider<SkinCubit>(create: (_) => SkinCubit()),
                BlocProvider<NotificationsCubit>(
                  create: (_) => NotificationsCubit(
                    notificationRepository,
                    sl<ServerConfigStore>(),
                    unreadPoll: const Duration(hours: 1),
                  ),
                ),
              ],
              child: const HomeShell(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('offers all three tabs', (tester) async {
    await pumpShell(tester);

    for (final label in ['Agents', 'PRs', 'Settings']) {
      expect(tabLabel(label), findsOneWidget);
    }
  });

  testWidgets('opens on the Agents tab', (tester) async {
    await pumpShell(tester);

    expect(tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex, 0);
  });

  testWidgets('switches tabs on tap', (tester) async {
    await pumpShell(tester);

    await tester.tap(tabLabel('Settings'));
    await settle(tester);

    expect(tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex, 2);
  });

  testWidgets('keeps every tab mounted so each keeps its state', (tester) async {
    await pumpShell(tester);

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).children.length, 3);
  });

  testWidgets('re-tapping the active tab scrolls its list to the top', (tester) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(
            sessions: [
              for (var i = 0; i < 40; i++)
                SessionModel(id: 's$i', projectId: 'proj', displayName: 'Session $i', status: 'working'),
            ],
          ),
        ),
      ),
    );
    await pumpShell(tester);

    final controller = HomeShell.controllerFor(0);
    expect(controller.hasClients, isTrue);

    controller.jumpTo(400);
    await tester.pump();
    expect(controller.offset, 400);

    await tester.tap(tabLabel('Agents'));
    await settle(tester);
    expect(controller.offset, 0);
  });

  testWidgets('tapping a different tab switches without scrolling the old one', (tester) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(
            sessions: [
              for (var i = 0; i < 40; i++)
                SessionModel(id: 's$i', projectId: 'proj', displayName: 'Session $i', status: 'working'),
            ],
          ),
        ),
      ),
    );
    await pumpShell(tester);

    final agents = HomeShell.controllerFor(0);
    agents.jumpTo(400);
    await tester.pump();

    await tester.tap(tabLabel('PRs'));
    await settle(tester);

    expect(HomeShell.selectedTab.value, 1);
    expect(agents.offset, 400);
  });

  ListView tabList(WidgetTester tester, int tab) => tester.widget<ListView>(
        find.byWidgetPredicate(
          (w) => w is ListView && w.controller == HomeShell.controllerFor(tab),
          skipOffstage: false,
        ),
      );

  testWidgets('every tab list starts below the glass top bar', (tester) async {
    await pumpShell(tester);
    expect((tabList(tester, 0).padding! as EdgeInsets).top, 44);
    expect(
      tester.widget<RefreshIndicator>(
        find.descendant(
          of: find.byType(SessionsScreen, skipOffstage: false),
          matching: find.byType(RefreshIndicator, skipOffstage: false),
          skipOffstage: false,
        ),
      ).edgeOffset,
      44,
    );
    expect((tabList(tester, 1).padding! as EdgeInsets).top, 44);
    expect(
      tester.widget<RefreshIndicator>(
        find.descendant(
          of: find.byType(PullRequestsScreen, skipOffstage: false),
          matching: find.byType(RefreshIndicator, skipOffstage: false),
          skipOffstage: false,
        ),
      ).edgeOffset,
      44,
    );
    expect((tabList(tester, 2).padding! as EdgeInsets).top, 60);
  });

  testWidgets('tab roots extend their body under the bar', (tester) async {
    await pumpShell(tester);
    for (final screen in [SessionsScreen, PullRequestsScreen, SettingsScreen]) {
      final scaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byType(screen, skipOffstage: false),
              matching: find.byType(Scaffold, skipOffstage: false),
              skipOffstage: false,
            )
            .first,
      );
      expect(scaffold.extendBodyBehindAppBar, isTrue, reason: '$screen');
    }
  });

  testWidgets('uses the floating glass tab bar', (tester) async {
    await pumpShell(tester);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(GlassTabBar), findsOneWidget);
    final bottomFade = tester.widgetList<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect)).where((e) => e.edge == ScrollEdge.bottom);
    expect(bottomFade.single.height, 120);
  });

  testWidgets('the bottom edge effect shows only while a tab has content under the bar', (tester) async {
    await pumpShell(tester);
    ScrollEdgeEffect bottomFade() =>
        tester.widgetList<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect)).singleWhere((e) => e.edge == ScrollEdge.bottom);
    Finder bottomBlur() => find.descendant(
          of: find.byWidgetPredicate((w) => w is ScrollEdgeEffect && w.edge == ScrollEdge.bottom),
          matching: find.byType(BackdropFilter),
        );
    final agents = HomeShell.controllerFor(0);
    expect(agents.position.maxScrollExtent, greaterThan(16));
    expect(bottomFade().visibility, 1);
    expect(bottomBlur(), findsOneWidget);

    agents.jumpTo(agents.position.maxScrollExtent);
    await tester.pump();
    expect(bottomFade().visibility, 0);
    expect(bottomBlur(), findsNothing);

    agents.jumpTo(agents.position.maxScrollExtent - 8);
    await tester.pump();
    expect(bottomFade().visibility, 0.5);

    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(HomeShell.controllerFor(1).position.maxScrollExtent, 0);
    expect(bottomFade().visibility, 0);
    expect(bottomBlur(), findsNothing);

    await tester.tap(tabLabel('Agents'));
    await settle(tester);
    expect(bottomFade().visibility, 0.5);
    agents.jumpTo(0);
  });

  testWidgets('the + button is regular glass in the tab bar row and opens spawn', (tester) async {
    await pumpShell(tester);
    final button = tester.widget<GlassButton>(find.byKey(HomeShell.spawnButtonKey));
    expect(button.prominent, isFalse);
    expect(button.diameter, GlassMetrics.tabBarHeight);
    final buttonRect = tester.getRect(find.byKey(HomeShell.spawnButtonKey));
    final barRect = tester.getRect(find.byType(GlassTabBar));
    expect(buttonRect.center.dy, closeTo(barRect.center.dy, 0.5));
    expect(buttonRect.left - barRect.right, GlassMetrics.bottomBarItemGap);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byKey(HomeShell.spawnButtonKey));
    await settle(tester);
    expect(find.text('route ${RoutesStrings.spawn}'), findsOneWidget);
  });

  testWidgets('the + button stays on every tab', (tester) async {
    await pumpShell(tester);
    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(find.byKey(HomeShell.spawnButtonKey), findsOneWidget);
    await tester.tap(tabLabel('Agents'));
    await settle(tester);
    expect(find.byKey(HomeShell.spawnButtonKey), findsOneWidget);
  });

  testWidgets('a tab tap fires exactly one haptic', (tester) async {
    final haptics = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpShell(tester);
    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(haptics, hasLength(1));
  });

  testWidgets('tab lists clear the floating tab bar and the + button', (tester) async {
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.success(
        GlobalResponse(
          data: BoardSnapshot(
            sessions: [
              for (var i = 0; i < 40; i++)
                SessionModel(id: 's$i', projectId: 'proj', displayName: 'Session $i', status: 'working'),
            ],
          ),
        ),
      ),
    );
    await pumpShell(tester);

    expect(HomeShell.contentBottomInset(0), 83);
    expect(HomeShell.contentBottomInset(100), 100);
    expect((tabList(tester, 0).padding! as EdgeInsets).bottom, 83 + 40);
    expect((tabList(tester, 1).padding! as EdgeInsets).bottom, 83 + 40);
    expect((tabList(tester, 2).padding! as EdgeInsets).bottom, 83 + 40);

    final controller = HomeShell.controllerFor(0);
    for (var i = 0; i < 20 && controller.offset < controller.position.maxScrollExtent; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
    }
    expect(controller.offset, controller.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 2000));
    await settle(tester);
    final lastCard = tester.getRect(find.byType(SessionCard).last);
    expect(lastCard.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(HomeShell.spawnButtonKey)).top));
    expect(lastCard.bottom, lessThanOrEqualTo(tester.getRect(find.byType(GlassTabBar)).top));
  });

  testWidgets('the Agents header names the desktop and its status, and tapping it opens the desktop switcher', (tester) async {
    connection().report(ConnectionOutcome.online);
    await pumpShell(tester);

    expect(find.text('Mac'), findsWidgets);
    expect(find.text('Updated just now'), findsWidgets);

    await tester.tap(find.byKey(DesktopStatusLine.tapKey).first);
    await settle(tester);
    await settle(tester);

    expect(find.byType(DesktopSwitcherList), findsOneWidget);
  });

  testWidgets('a cached board stays up under an offline header on a cold start', (tester) async {
    when(() => repository.cachedBoard()).thenAnswer(
      (_) async => Replicated(
        value: const BoardSnapshot(
          sessions: [SessionModel(id: 'w-1', projectId: 'proj', displayName: 'Cached worker', status: 'working')],
        ),
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    when(() => repository.getBoard()).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'down', message: 'down', statusCode: -6)),
    );
    connection().report(ConnectionOutcome.unreachable);
    await pumpShell(tester);

    expect(find.text('Cached worker'), findsOneWidget);
    expect(find.text('Offline · last seen 5m ago'), findsWidgets);
    await tester.pump(ConnectionBackoff.initial);
  });

  group('connection-aware chrome', () {
    final notified = <String>[];

    setUp(() {
      notified.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(Haptics.channelName),
        (call) async {
          notified.add(call.arguments as String);
          return null;
        },
      );
      sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
        (mode, _) => ManualConnectCubit(_MockPairingRepository(), sl<ServerConfigStore>(), mode: mode),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(Haptics.channelName), null);
    });

    double spawnOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(HomeShell.spawnButtonKey), matching: find.byType(AnimatedOpacity)).first,
        )
        .opacity;

    testWidgets('the + dims while the desktop is unreachable, and explains itself instead of opening Spawn', (tester) async {
      connection().report(ConnectionOutcome.unreachable);
      await pumpShell(tester);

      expect(spawnOpacity(tester), HomeShell.offlineSpawnOpacity);
      await tester.tap(find.byKey(HomeShell.spawnButtonKey));
      await settle(tester);

      expect(notified, ['error']);
      expect(find.text(HomeShell.offlineSpawnMessage), findsOneWidget);
      expect(find.text('route /spawn'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('the + dims while the desktop rejects the password, and explains itself instead of opening Spawn', (tester) async {
      connection().report(ConnectionOutcome.auth);
      await pumpShell(tester);
      await tester.tap(find.byKey(AppSheet.closeKey));
      await settle(tester);
      await settle(tester);

      expect(spawnOpacity(tester), HomeShell.offlineSpawnOpacity);
      await tester.tap(find.byKey(HomeShell.spawnButtonKey));
      await settle(tester);

      expect(notified, ['error']);
      expect(find.text(HomeShell.offlineSpawnMessage), findsOneWidget);
      expect(find.text('route /spawn'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('the + opens Spawn while the desktop answers', (tester) async {
      connection().report(ConnectionOutcome.online);
      await pumpShell(tester);

      expect(spawnOpacity(tester), 1);
      await tester.tap(find.byKey(HomeShell.spawnButtonKey));
      await settle(tester);

      expect(find.text('route /spawn'), findsOneWidget);
    });

    testWidgets('the re-pair sheet opens once per auth failure', (tester) async {
      await pumpShell(tester);

      connection().report(ConnectionOutcome.auth);
      await settle(tester);
      connection().report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsOneWidget);

      await tester.tap(find.byKey(AppSheet.closeKey));
      await settle(tester);
      await settle(tester);
      expect(find.byType(RePairForm), findsNothing);

      connection().report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsNothing);

      connection().report(ConnectionOutcome.online);
      connection().report(ConnectionOutcome.auth);
      await settle(tester);
      expect(find.byType(RePairForm), findsOneWidget);
    });

    testWidgets('after the sheet is dismissed, tapping Needs re-pairing in the header reopens it', (tester) async {
      await pumpShell(tester);
      connection().report(ConnectionOutcome.auth);
      await settle(tester);
      await tester.tap(find.byKey(AppSheet.closeKey));
      await settle(tester);
      await settle(tester);
      expect(find.byType(RePairForm), findsNothing);

      await tester.tap(find.byKey(DesktopStatusLine.tapKey).first);
      await settle(tester);

      expect(find.byType(RePairForm), findsOneWidget);
      expect(find.text('route /connections'), findsNothing);
    });

    testWidgets('an auth failure from before the shell mounted still opens the re-pair sheet', (tester) async {
      connection().report(ConnectionOutcome.auth);
      await pumpShell(tester);
      await settle(tester);

      expect(find.byType(RePairForm), findsOneWidget);
    });
  });
}
