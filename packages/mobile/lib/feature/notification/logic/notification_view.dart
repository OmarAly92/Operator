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

/// The id is escaped because the consumer (`resolveDeepLinkPath`) decodes it —
/// leaving it raw makes a `%` or a `/` in an id either mangle the path or fail
/// to resolve.
String notificationTarget({required String type, String? sessionId}) =>
    type == 'needs_input' && (sessionId ?? '').isNotEmpty
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
