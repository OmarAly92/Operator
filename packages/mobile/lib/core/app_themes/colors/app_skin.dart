import 'package:flutter/material.dart';

abstract class AppSkin {
  const AppSkin();

  /// The Material [ThemeMode] this skin drives — [ThemeMode.light] or
  /// [ThemeMode.dark]. [MaterialApp] receives it as its themeMode so the
  /// framework picks the matching [ThemeData]. Example: LightSkin returns
  /// [ThemeMode.light], DarkSkin returns [ThemeMode.dark].
  ThemeMode get themeMode;

  /// The base color of the whole app, painted behind every screen. Example:
  /// the color filling the space behind the Kanban board and its columns.
  Color get bgBase;

  /// The color of the app's side navigation rail or drawer. Example: the
  /// fill behind the sidebar listing the orchestrator, PR review, and
  /// settings tabs.
  Color get bgSide;

  /// The fill of a single Kanban column, distinguishing it from the board's
  /// base background. Example: the background behind the "In Review"
  /// column and its stack of session cards.
  Color get bgColumn;

  /// The color of raised, self-contained blocks sitting above the base
  /// background. Example: the fill of a session card on the Kanban board.
  Color get bgSurface;

  /// The color of surfaces raised a step above [bgSurface], for elements
  /// meant to sit visually on top of ordinary cards. Example: the fill of
  /// an open dropdown menu or popover triggered from a session card.
  Color get bgElevated;

  /// The hover state of [bgElevated], shown while the pointer sits over an
  /// elevated element. Example: the fill of a menu item as the cursor
  /// passes over it in a session card's context menu.
  Color get bgElevatedHover;

  /// A barely-there fill used to set apart a region without a hard
  /// boundary. Example: the faint shading behind a collapsed section of
  /// the settings screen.
  Color get bgSubtle;

  /// The strongest text color, for content that must read first. Example:
  /// the session title on a Kanban card.
  Color get textPrimary;

  /// The medium-emphasis text color for supporting copy. Example: the
  /// branch name shown under a session card's title.
  Color get textSecondary;

  /// The low-emphasis text color for de-emphasized detail. Example: the
  /// relative timestamp on a chat message.
  Color get textTertiary;

  /// The faintest text color, for content that should barely register.
  /// Example: a placeholder hint inside the terminal's command input.
  Color get textFaint;

  /// The lightest border weight, for divisions that should almost
  /// disappear. Example: the hairline separating rows in the notifications
  /// list.
  Color get borderSubtle;

  /// The standard border weight used around most bordered elements.
  /// Example: the outline around a session card on the Kanban board.
  Color get borderDefault;

  /// The heaviest border weight, for emphasis or a focused state. Example:
  /// the outline around a session card while it is being dragged between
  /// columns.
  Color get borderStrong;

  /// The conductor. Represents the orchestrator/coordinator itself.
  /// Example: the icon color for the orchestrator tab in the sidebar.
  Color get blue;

  /// A working agent. Represents a session actively running. Example: the
  /// status dot on a session card that is currently executing.
  Color get orange;

  /// Needs your input. Represents a session awaiting a decision. Example:
  /// the badge on a session card that is paused waiting for approval.
  Color get amber;

  /// Failing. Example: the status pill on a session card whose last run
  /// errored out.
  Color get red;

  /// Merged. Example: the status pill on a pull request card that has
  /// been merged.
  Color get purple;

  /// Passed. Example: the status pill on a session card whose checks all
  /// succeeded.
  Color get green;

  /// A soft, translucent fill of [blue], used behind blue-tinted content
  /// rather than as a foreground color. Example: the pill background for
  /// the orchestrator tab when it is the active tab.
  Color get tintBlue;

  /// A soft, translucent fill of [orange], used behind orange-tinted
  /// content rather than as a foreground color. Example: the pill
  /// background for a session shown as actively working.
  Color get tintOrange;

  /// A soft, translucent fill of [amber], used behind amber-tinted content
  /// rather than as a foreground color. Example: the pill background for a
  /// session awaiting your input.
  Color get tintAmber;

  /// A soft, translucent fill of [red], used behind red-tinted content
  /// rather than as a foreground color. Example: the pill background for a
  /// session shown as failing.
  Color get tintRed;

  /// A soft, translucent fill of [green], used behind green-tinted content
  /// rather than as a foreground color. Example: the pill background for a
  /// session shown as passed.
  Color get tintGreen;

  /// A soft, translucent fill of [purple], used behind purple-tinted
  /// content rather than as a foreground color. Example: the pill
  /// background for a pull request shown as merged.
  Color get tintPurple;

  /// The text and icon color used on top of [accent] fills. Example: the
  /// label color of the primary "Launch session" button.
  Color get onAccent;

  /// The dimmed layer covering the screen behind dialogs and sheets.
  /// Example: the dark overlay behind an open session's terminal sheet.
  Color get scrim;

  /// The app's primary interactive color, used for default actions and
  /// emphasis outside the six state hues. Example: the fill of the
  /// primary "Launch session" button on the orchestrator view.
  Color get accent;

  /// A soft, translucent fill of [accent]. Example: the highlighted
  /// background of the currently selected tab in the sidebar.
  Color get accentTint;

  /// The color drawing the eye to something that needs attention, outside
  /// the per-session state hues. Example: the dot on the notifications
  /// bell icon when there are unread notifications.
  Color get attention;
}
