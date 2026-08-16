import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _FakeBuildContext extends Fake implements BuildContext {}

class _MockSessionsCubit extends Mock implements SessionsCubit {}

class _MockNotificationsCubit extends MockCubit<NotificationsState> implements NotificationsCubit {}

class _MockTerminalCubit extends MockCubit<TerminalState> implements TerminalCubit {}

class _MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}

void main() {
  Widget builtWidgetFor(String routeName, {Object? arguments}) {
    final route = AppRouter.generateRoute(RouteSettings(name: routeName, arguments: arguments)) as MaterialPageRoute;
    return route.builder(_FakeBuildContext());
  }

  test('routes onboarding directly to its screen', () {
    expect(builtWidgetFor(RoutesStrings.onboarding), isA<OnboardingScreen>());
  });

  test('routes pairing scan, manual connect, and sessions through a BlocProvider', () async {
    await sl.reset();
    sl.registerLazySingleton<SessionsCubit>(_MockSessionsCubit.new);
    sl.registerLazySingleton<NotificationsCubit>(_MockNotificationsCubit.new);

    expect(builtWidgetFor(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true}), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.manualConnect), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.sessions), isA<MultiBlocProvider>());

    await sl.reset();
  });

  test('types the manual connect route so pushNamed<bool> can cast it', () {
    final route = AppRouter.generateRoute(const RouteSettings(name: RoutesStrings.manualConnect));
    expect(route, isA<Route<bool?>>());
  });

  test('falls through to the error widget for an unknown route', () {
    expect(builtWidgetFor('/nowhere'), isA<AppScaffold>());
  });

  test('routes the terminal through a BlocProvider', () async {
    await sl.reset();
    sl.registerLazySingleton<SessionsCubit>(_MockSessionsCubit.new);
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>((_, _) => _MockTerminalCubit());
    sl.registerFactoryParam<InterfaceSwitchCubit, String, void>((_, _) => _MockInterfaceSwitchCubit());

    expect(
      builtWidgetFor(
        RoutesStrings.terminal,
        arguments: {
          'args': const TerminalArgs(id: 'h-1', sessionId: 's-1', title: 'Worktree shell', shellOnly: true),
        },
      ),
      isA<MultiBlocProvider>(),
    );

    await sl.reset();
  });

  test('routes /notifications to the notifications screen', () {
    final route = AppRouter.generateRoute(const RouteSettings(name: RoutesStrings.notifications));

    expect(route, isA<MaterialPageRoute<dynamic>>());
    expect(route.settings.name, RoutesStrings.notifications);
  });
}
