import 'package:flutter/material.dart';

import 'snack_view.dart';

/// One shown snack and the key that reaches its live view.
class Snack {
  Snack({
    required this.message,
    required this.icon,
    required this.duration,
    required this.maxLines,
    this.backgroundColor,
    this.foregroundColor,
    this.iconBackgroundColor,
    this.actionLabel,
    this.onAction,
  });

  final GlobalKey<SnackViewState> key = GlobalKey();
  final String message;
  final IconData? icon;
  final Duration duration;
  final int maxLines;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? iconBackgroundColor;
  final String? actionLabel;
  final VoidCallback? onAction;
}
