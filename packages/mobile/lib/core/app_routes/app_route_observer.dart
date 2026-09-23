import 'package:flutter/widgets.dart';

sealed class AppRouteObserver {
  static final RouteObserver<PageRoute<dynamic>> instance = RouteObserver<PageRoute<dynamic>>();
}
