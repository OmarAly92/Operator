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
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/mux/session_patch.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/feature/notification/data/model/notification_page_model.dart';
import 'package:operator_mobile/feature/notification/data/model/params/get_notifications_params.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

class _MockSessionsRepository extends Mock implements SessionsRepository {}

class _MockMuxClient extends Mock implements MuxClient {}

class _MockPullRequestRepository extends Mock implements PullRequestRepository {}

class _MockServerConfigStore extends Mock implements ServerConfigStore {}

class _MockNotificationRepository extends Mock implements NotificationRepository {}

class _MockDesktopsRepository extends Mock implements DesktopsRepository {}

void main() {
  late _MockSessionsRepository repository;
  late _MockMuxClient mux;
  late _MockNotificationRepository notificationRepository;

  setUpAll(() {
    registerFallbackValue(const GetNotificationsParams());
  });

  setUp(() async {
    HomeShell.selectedTab.value = 0;
    SharedPreferences.setMockInitialValues({});
    await CacheHelper.init();
    repository = _MockSessionsRepository();
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
    when(() => notificationRepository.getPhoneAlerts()).thenAnswer(
      (_) async => Result.success(const PhoneAlertStatusModel(enabled: false, claimed: false)),
    );
    await sl.reset();
    sl.registerFactory<PullRequestCubit>(() => PullRequestCubit(_MockPullRequestRepository()));
    final serverConfigStore = _MockServerConfigStore();
    when(() => serverConfigStore.current).thenReturn(null);
    when(() => serverConfigStore.changes).thenAnswer((_) => const Stream.empty());
    sl.registerLazySingleton<ServerConfigStore>(() => serverConfigStore);
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

  tearDown(() => sl.reset());

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

  testWidgets('the + button is prominent glass and opens spawn', (tester) async {
    await pumpShell(tester);
    expect(tester.widget<GlassButton>(find.byKey(HomeShell.spawnButtonKey)).prominent, isTrue);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byKey(HomeShell.spawnButtonKey));
    await settle(tester);
    expect(find.text('route ${RoutesStrings.spawn}'), findsOneWidget);
  });

  testWidgets('the + button shows only on the Agents tab', (tester) async {
    await pumpShell(tester);
    await tester.tap(tabLabel('PRs'));
    await settle(tester);
    expect(find.byKey(HomeShell.spawnButtonKey), findsNothing);
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
    expect((tabList(tester, 0).padding! as EdgeInsets).bottom, 83 + 12 + 44);
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
}
