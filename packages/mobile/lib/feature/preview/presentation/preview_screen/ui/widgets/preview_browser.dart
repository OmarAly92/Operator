import 'package:flutter/material.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PreviewBrowser extends StatefulWidget {
  const PreviewBrowser({super.key, required this.preview, required this.onError});

  final PreviewModel preview;
  final void Function(String message) onError;

  @override
  State<PreviewBrowser> createState() => _PreviewBrowserState();
}

class _PreviewBrowserState extends State<PreviewBrowser> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onWebResourceError: (error) => widget.onError(
          error.description.isEmpty ? 'The preview could not be loaded.' : error.description,
        ),
        onHttpError: (error) => widget.onError(
          'Preview returned HTTP ${error.response?.statusCode ?? 0}.',
        ),
      ),
    );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PreviewBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.url != widget.preview.url) _load();
  }

  /// The daemon's preview route sits behind the connection password, so without
  /// this header the WebView 401s and renders the JSON error body. An external
  /// dev server is never authenticated and must never see the password.
  void _load() {
    final password = sl<ServerConfigStore>().current?.password ?? '';
    _controller.loadRequest(
      Uri.parse(widget.preview.url),
      headers: widget.preview.authenticated && password.isNotEmpty
          ? {'Authorization': 'Bearer $password'}
          : const {},
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.skin.bgBase,
    child: WebViewWidget(controller: _controller),
  );
}
