import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';

sealed class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RoutesStrings.onboarding:
        return MaterialPageRoute(builder: (context) => const OnboardingScreen(), settings: settings);

      case RoutesStrings.pairingScan:
        final args = settings.arguments as Map<String, dynamic>?;
        final fromOnboarding = args?['fromOnboarding'] as bool? ?? false;
        return MaterialPageRoute(
          builder: (context) => BlocProvider(
            create: (_) => sl<PairingScanCubit>(param1: fromOnboarding),
            child: const PairingScanScreen(),
          ),
          settings: settings,
        );

      case RoutesStrings.manualConnect:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<ManualConnectCubit>(), child: const ManualConnectScreen()),
          settings: settings,
        );

      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<SessionsCubit>(), child: const SessionsScreen()),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (context) => const AppScaffold(appBar: GlobalAppbar.sub(), body: AppErrorWidget()),
          settings: settings,
        );
    }
  }
}
