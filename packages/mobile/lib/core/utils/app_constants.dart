/// Radius scale extracted from the design prototype's actual `borderRadius`
/// literals (`docs/design/components.md`) — not an invented generic scale.
/// Each value is backed by real, repeated usage in the prototype's Component
/// class style objects.
sealed class AppConstants {
  /// 4px — smallest, used for tiny square icons (e.g. agent logo thumbnail).
  static const double radiusXs = 4;

  /// 6px — shimmer skeleton text lines, small mono command chips.
  static const double radiusSm = 6;

  /// 7px — small toggle/segmented buttons (theme toggle, state toggle,
  /// zoom group, terminal quick-tag borders).
  static const double radiusChip = 7;

  /// 8px — icon buttons (connection more/cmd-trigger), small action buttons
  /// (start, permission allow/deny), command cards.
  static const double radiusMd = 8;

  /// 10px — form inputs (sheet input, spawn text fields), medium icon
  /// wraps, theme-toggle-row track, permission card.
  static const double radiusLg = 10;

  /// 12px — primary/secondary/sheet buttons, kill button.
  static const double radiusButton = 12;

  /// 14px — cards and card-like containers (session card, connection
  /// group, dialog, stat card, orchestrator card, PR card, settings
  /// group).
  static const double radiusCard = 14;

  /// 18px — the nav/PR-filter segmented stepper pill (one-off, larger than
  /// [radiusButton] but not a full pill).
  static const double radiusStepper = 18;

  /// 999px — fully pill/circular corners (status chips, sheet handle,
  /// skeleton pills, the empty-state primary button, toggle thumbs).
  static const double radiusPill = 999;
}
