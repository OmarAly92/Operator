import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart';

class _MockConnectionsCubit extends MockCubit<ConnectionsState> implements ConnectionsCubit {}

class _RecordingObserver extends NavigatorObserver {
  final List<RouteSettings> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings);
}

const _mac = DesktopModel(id: 'a', name: 'Mac', host: '10.0.0.5', port: '3011', secure: false, isActive: true);
const _imac = DesktopModel(id: 'b', name: 'iMac', host: '10.0.0.6', port: '3011', secure: false, isActive: false);

void main() {
  late _MockConnectionsCubit cubit;
  late _RecordingObserver observer;

  setUpAll(() => registerFallbackValue(TargetPlatform.iOS));

  setUp(() {
    cubit = _MockConnectionsCubit();
    observer = _RecordingObserver();
    when(() => cubit.desktops).thenReturn(const [_mac, _imac]);
    when(() => cubit.connectingId).thenReturn(null);
    when(() => cubit.errors).thenReturn({});
    whenListen(cubit, const Stream<ConnectionsState>.empty(), initialState: const DesktopsUpdatedState([_mac, _imac]));
  });

  Future<void> pumpBody(WidgetTester tester) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            navigatorObservers: [observer],
            routes: {
              RoutesStrings.onboarding: (_) => const Scaffold(body: Text('Onboarding screen')),
              RoutesStrings.pairingScan: (_) => const Scaffold(body: Text('Scan screen')),
            },
            home: BlocProvider<ConnectionsCubit>.value(
              value: cubit,
              child: const Scaffold(body: ConnectionsBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders every desktop by name and marks only the active one with a dot', (tester) async {
    await pumpBody(tester);

    expect(find.text('Mac'), findsOneWidget);
    expect(find.text('iMac'), findsOneWidget);
    expect(find.byKey(const Key('active-dot-a')), findsOneWidget);
    expect(find.byKey(const Key('active-dot-b')), findsNothing);
  });

  testWidgets('an auth failure on a row offers Scan again, which opens the scanner', (tester) async {
    final copy = describeConnectionFailure(
      ConnectionFailure.auth,
      host: '10.0.0.5',
      port: '3011',
      platform: TargetPlatform.iOS,
    );
    when(() => cubit.errors).thenReturn({'a': copy});
    whenListen(cubit, const Stream<ConnectionsState>.empty(), initialState: ConnectFailureState('a', copy));

    await pumpBody(tester);

    expect(find.text(copy.message), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);

    await tester.tap(find.text('Scan again'));
    await tester.pumpAndSettle();

    expect(find.text('Scan screen'), findsOneWidget);
    final route = observer.pushed.last;
    expect(route.name, RoutesStrings.pairingScan);
    expect(route.arguments, {'fromOnboarding': true});
  });

  testWidgets('a non-auth failure shows the message without Scan again', (tester) async {
    final copy = describeConnectionFailure(
      ConnectionFailure.unreachable,
      host: '10.0.0.5',
      port: '3011',
      platform: TargetPlatform.android,
    );
    when(() => cubit.errors).thenReturn({'a': copy});
    whenListen(cubit, const Stream<ConnectionsState>.empty(), initialState: ConnectFailureState('a', copy));

    await pumpBody(tester);

    expect(find.text(copy.message), findsOneWidget);
    expect(find.text('Scan again'), findsNothing);
  });

  testWidgets('tapping a row asks the cubit to connect to that desktop', (tester) async {
    when(() => cubit.connectTo(any(), any())).thenAnswer((_) async {});

    await pumpBody(tester);
    await tester.tap(find.text('iMac'));
    await tester.pump();

    verify(() => cubit.connectTo('b', any())).called(1);
  });

  testWidgets('Pair another desktop pushes onboarding flagged fromDesktops', (tester) async {
    await pumpBody(tester);

    await tester.tap(find.text('Pair another desktop'));
    await tester.pumpAndSettle();

    final route = observer.pushed.last;
    expect(route.name, RoutesStrings.onboarding);
    expect(route.arguments, {'fromDesktops': true});
    expect(find.text('Onboarding screen'), findsOneWidget);
  });
}
