import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/ui/notifications_screen.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/onboarding_screen.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/manual_connect_screen.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/pairing_scan_screen.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/ui/preview_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/session_route/ui/session_route_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/spawn_screen.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart';

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
        return MaterialPageRoute<bool>(
          builder: (context) => BlocProvider(create: (_) => sl<ManualConnectCubit>(), child: const ManualConnectScreen()),
          settings: settings,
        );

      case RoutesStrings.sessions:
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: sl<SessionsCubit>()),
              BlocProvider.value(value: sl<NotificationsCubit>()),
            ],
            child: const HomeShell(),
          ),
          settings: settings,
        );

      case RoutesStrings.notifications:
        return MaterialPageRoute(
          builder: (context) => BlocProvider.value(
            value: sl<NotificationsCubit>(),
            child: const NotificationsScreen(),
          ),
          settings: settings,
        );

      case RoutesStrings.spawn:
        return MaterialPageRoute(
          builder: (context) => BlocProvider(create: (_) => sl<SpawnCubit>(), child: const SpawnScreen()),
          settings: settings,
          fullscreenDialog: true,
        );

      case RoutesStrings.session:
        final args = settings.arguments as Map<String, dynamic>?;
        final sessionId = args?['sessionId'] as String? ?? '';
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider.value(value: sl<SessionsCubit>()),
              BlocProvider<ChatCubit>(create: (_) => sl<ChatCubit>(param1: sessionId)),
              BlocProvider<InterfaceSwitchCubit>(
                create: (_) => sl<InterfaceSwitchCubit>(param1: sessionId),
              ),
            ],
            child: SessionRouteScreen(sessionId: sessionId),
          ),
          settings: settings,
        );

      case RoutesStrings.terminal:
        final args = (settings.arguments as Map<String, dynamic>?)?['args'] as TerminalArgs?;
        final terminalArgs =
            args ?? const TerminalArgs(id: '', sessionId: '', title: 'Terminal');
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider<TerminalCubit>(create: (_) => sl<TerminalCubit>(param1: terminalArgs)),
              BlocProvider<InterfaceSwitchCubit>(
                create: (_) => sl<InterfaceSwitchCubit>(param1: terminalArgs.shellOnly ? '' : terminalArgs.sessionId),
              ),
              BlocProvider<PreviewCubit>(
                create: (_) => sl<PreviewCubit>(param1: terminalArgs.sessionId, param2: null),
              ),
            ],
            child: const TerminalScreen(),
          ),
          settings: settings,
        );

      case RoutesStrings.preview:
        final args = settings.arguments as Map<String, dynamic>?;
        final sessionId = args?['sessionId'] as String? ?? '';
        return MaterialPageRoute(
          builder: (context) => BlocProvider<PreviewCubit>(
            create: (_) => sl<PreviewCubit>(
              param1: sessionId,
              param2: args?['previewUrl'] as String?,
            ),
            child: PreviewScreen(title: args?['title'] as String? ?? 'Preview'),
          ),
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
