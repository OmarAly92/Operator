import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/app_router.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/themes/app_themes.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/onboarding/logic/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await CacheHelper.init();
  await ServiceLocator.init();
  await sl<ServerConfigStore>().load();

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

class OperatorApp extends StatelessWidget {
  const OperatorApp({required this.initialRoute, super.key});

  final String initialRoute;

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
                  debugShowCheckedModeBanner: false,
                  theme: AppThemes.fromSkin(skin),
                  themeMode: skin.themeMode,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  initialRoute: initialRoute,
                  onGenerateInitialRoutes: (name) => [AppRouter.generateRoute(RouteSettings(name: name))],
                  onGenerateRoute: AppRouter.generateRoute,
                ),
              ),
            );
          },
        ),
      );
}
