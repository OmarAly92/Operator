import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

const String kDeepLinkScheme = 'aomobile';

/// The PRs tab's index in `HomeShell`.
const int kPrsTabIndex = 2;

class DeepLinkTarget extends Equatable {
  const DeepLinkTarget({required this.route, this.arguments, this.tabIndex});

  final String route;
  final Map<String, dynamic>? arguments;
  final int? tabIndex;

  @override
  List<Object?> get props => [route, arguments, tabIndex];
}

/// `aomobile://session/abc` parses with `session` as the host, while
/// `aomobile:///session/abc` puts it in the path — both forms reach a phone, so
/// both are flattened to the same segment list.
///
/// `Uri.pathSegments` is already percent-decoded, so decoding it again would
/// both mangle a legitimately escaped id and throw on what is left of a
/// truncated escape.
DeepLinkTarget? resolveDeepLink(Uri uri) {
  if (uri.scheme != kDeepLinkScheme) return null;
  final segments = [
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((segment) => segment.isNotEmpty),
  ];
  return _resolveSegments(segments);
}

/// The path form `notificationTarget` produces, so a tray tap and a history tap
/// cannot disagree about where a notification leads. Unlike a parsed [Uri],
/// these segments arrive still encoded, so they are decoded here — and a
/// malformed escape resolves to nothing rather than throwing at the caller.
DeepLinkTarget? resolveDeepLinkPath(String path) {
  if (!path.startsWith('/')) return null;
  final decoded = <String>[];
  for (final segment in path.split('/').where((segment) => segment.isNotEmpty)) {
    try {
      decoded.add(Uri.decodeComponent(segment));
    } catch (_) {
      return null;
    }
  }
  return _resolveSegments(decoded);
}

DeepLinkTarget? _resolveSegments(List<String> segments) {
  if (segments.isEmpty) return null;
  final id = segments.length > 1 ? segments[1] : '';

  switch (segments.first) {
    case 'session':
      if (id.isEmpty) return null;
      return DeepLinkTarget(route: RoutesStrings.session, arguments: {'sessionId': id});
    case 'terminal':
      if (id.isEmpty) return null;
      return DeepLinkTarget(
        route: RoutesStrings.terminal,
        arguments: {'args': TerminalArgs(id: id, sessionId: id, title: 'Terminal')},
      );
    case 'prs':
      return const DeepLinkTarget(route: RoutesStrings.sessions, tabIndex: kPrsTabIndex);
    case 'notifications':
      return const DeepLinkTarget(route: RoutesStrings.notifications);
    default:
      return null;
  }
}
