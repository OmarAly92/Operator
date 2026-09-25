import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

class NotificationVisual extends Equatable {
  const NotificationVisual({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  List<Object?> get props => [icon, color, label];
}

NotificationVisual notificationVisual(AppSkin skin, String type) => switch (type) {
  'needs_input' => NotificationVisual(
    icon: Icons.chat_bubble_outline,
    color: skin.amber,
    label: 'Needs input',
  ),
  'turn_finished' => NotificationVisual(
    icon: Icons.check_circle_outline,
    color: skin.green,
    label: 'Finished',
  ),
  'agent_exited' => NotificationVisual(
    icon: Icons.stop_circle_outlined,
    color: skin.red,
    label: 'Exited',
  ),
  'ready_to_merge' => NotificationVisual(
    icon: Icons.merge_outlined,
    color: skin.green,
    label: 'Ready to merge',
  ),
  'pr_merged' => NotificationVisual(
    icon: Icons.merge_outlined,
    color: skin.blue,
    label: 'Merged',
  ),
  'pr_closed_unmerged' => NotificationVisual(
    icon: Icons.cancel_outlined,
    color: skin.red,
    label: 'Closed',
  ),
  _ => NotificationVisual(
    icon: Icons.notifications_none,
    color: skin.textTertiary,
    label: type.isEmpty ? 'Notification' : type,
  ),
};

const _sessionTypes = {'needs_input', 'turn_finished', 'agent_exited'};

/// The id is escaped because the consumer (`resolveDeepLinkPath`) decodes it —
/// leaving it raw makes a `%` or a `/` in an id either mangle the path or fail
/// to resolve.
String notificationTarget({required String type, String? sessionId}) =>
    _sessionTypes.contains(type) && (sessionId ?? '').isNotEmpty
    ? '/session/${Uri.encodeComponent(sessionId!)}'
    : '/prs';

String relativeTime(String iso, [DateTime? now]) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final elapsed = (now ?? DateTime.now()).difference(then);
  final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  if (seconds < 60) return 'now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d';
  return '${days ~/ 7}w';
}

final _fence = RegExp(r'```[^\n]*');
final _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final _heading = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
final _quote = RegExp(r'^\s{0,3}>\s?', multiLine: true);
final _bullet = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+', multiLine: true);
final _strong = RegExp(r'(\*\*|__)(.+?)\1');
final _emphasis = RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])');
final _strike = RegExp(r'~~(.+?)~~');
final _whitespace = RegExp(r'\s+');

String plainPreview(String markdown) => markdown
    .replaceAll(_fence, ' ')
    .replaceAllMapped(_image, (m) => m[1]!)
    .replaceAllMapped(_link, (m) => m[1]!)
    .replaceAll(_heading, '')
    .replaceAll(_quote, '')
    .replaceAll(_bullet, '')
    .replaceAllMapped(_strong, (m) => m[2]!)
    .replaceAllMapped(_strike, (m) => m[1]!)
    .replaceAllMapped(_emphasis, (m) => m[1]!)
    .replaceAll('`', '')
    .replaceAll(_whitespace, ' ')
    .trim();
