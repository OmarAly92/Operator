import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/widgets/failure_widgets/app_error_widget.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

sealed class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RoutesStrings.splash:
        return MaterialPageRoute(
          builder: (context) => const AppScaffold(body: SizedBox.shrink()),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (context) => const AppScaffold(
            appBar: GlobalAppbar.sub(),
            body: AppErrorWidget(),
          ),
          settings: settings,
        );
    }
  }
}
