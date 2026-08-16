import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/themes/app_themes.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await CacheHelper.init();
  await ServiceLocator.init();
  await sl<ServerConfigStore>().load();

  final packageInfo = await PackageInfo.fromPlatform();
  TelemetryRuntime.init(
    context: TelemetryContextInput(
      platformOs: Platform.operatingSystem,
      isPhysicalDevice: true,
      dev: kDebugMode,
      appVersion: packageInfo.version,
    ),
  );
  unawaited(TelemetryRuntime.active());

  final configured = sl<ServerConfigStore>().current != null;
  final skipped = (CacheHelper.get(CacheKeys.onboardingSkipped) as bool?) ?? false;
  final initialRoute = shouldOnboard(configured: configured, skipped: skipped)
      ? RoutesStrings.onboarding
      : RoutesStrings.sessions;

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: OperatorApp(initialRoute: initialRoute),
    ),
  );
}

class OperatorApp extends StatefulWidget {
  const OperatorApp({required this.initialRoute, super.key});

  final String initialRoute;

  @override
  State<OperatorApp> createState() => _OperatorAppState();
}

class _OperatorAppState extends State<OperatorApp> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => unawaited(TelemetryRuntime.active()),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(sl<DeepLinkService>().start());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => SkinCubit(),
        child: BlocBuilder<SkinCubit, SkinState>(
          buildWhen: (previous, current) => current is SkinChangedState,
          builder: (context, state) {
            final skin = context.read<SkinCubit>().skin;
            return SkinScope(
              skin: skin,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                minTextAdapt: true,
                builder: (context, child) => MaterialApp(
                  navigatorKey: sl<GlobalKey<NavigatorState>>(),
                  debugShowCheckedModeBanner: false,
                  theme: AppThemes.fromSkin(skin),
                  themeMode: skin.themeMode,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  initialRoute: widget.initialRoute,
                  onGenerateInitialRoutes: (name) => [AppRouter.generateRoute(RouteSettings(name: name))],
                  onGenerateRoute: AppRouter.generateRoute,
                ),
              ),
            );
          },
        ),
      );
}
