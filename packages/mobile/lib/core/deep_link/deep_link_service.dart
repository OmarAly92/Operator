import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/deep_link/deep_link_target.dart';

abstract class AppLinkSource {
  Future<Uri?> initialLink();

  Stream<Uri> get linkStream;
}

class AppLinksSource implements AppLinkSource {
  AppLinksSource([AppLinks? links]) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> get linkStream => _links.uriLinkStream;
}

class DeepLinkService {
  DeepLinkService(this._source, this._navigatorKey);

  final AppLinkSource _source;
  final GlobalKey<NavigatorState> _navigatorKey;

  StreamSubscription<Uri>? _subscription;

  /// The cold-start link is read before subscribing: the stream only carries
  /// links that arrive while the app is already alive, so the launch tap would
  /// otherwise be lost.
  Future<void> start() async {
    final initial = await _source.initialLink();
    if (initial != null) handle(initial);
    _subscription = _source.linkStream.listen(handle);
  }

  bool handle(Uri uri) {
    final target = resolveDeepLink(uri);
    if (target == null) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;

    final tabIndex = target.tabIndex;
    if (tabIndex != null) {
      HomeShell.selectedTab.value = tabIndex;
      navigator.popUntil((route) => route.isFirst);
      return true;
    }

    navigator.pushNamed(target.route, arguments: target.arguments);
    return true;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
