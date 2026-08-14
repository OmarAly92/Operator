import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';

class _FakeBuildContext extends Fake implements BuildContext {}

class _MockSessionsCubit extends Mock implements SessionsCubit {}

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

    expect(builtWidgetFor(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true}), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.manualConnect), isA<BlocProvider>());
    expect(builtWidgetFor(RoutesStrings.sessions), isA<BlocProvider>());

    await sl.reset();
  });

  test('types the manual connect route so pushNamed<bool> can cast it', () {
    final route = AppRouter.generateRoute(const RouteSettings(name: RoutesStrings.manualConnect));
    expect(route, isA<Route<bool?>>());
  });

  test('falls through to the error widget for an unknown route', () {
    expect(builtWidgetFor('/nowhere'), isA<AppScaffold>());
  });
}
