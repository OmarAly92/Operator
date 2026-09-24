# Mobile glass chrome — design

Date: 2026-09-24. Branch: `feat/mobile-ios-polish` (worktree
`/Users/omaraly/development/AI/Operator-ios-polish`). Package: `packages/mobile`.

## Why

Project 1 (`2026-09-23-mobile-liquid-glass-engine-design.md`) built and tuned the glass engine,
but proved it only in the debug glass lab. None of the real screens changed. This project puts
the glass on the real app's chrome: the tab bar, the top bars, the sheets and the primary **+**
button.

The rest of the original "project 2" is a separate follow-up project with its own spec: Cupertino
routes with swipe-back, large titles, action sheets and context menus, iOS controls, SF-style
icons, and a haptics map.

## Decisions (user, 2026-09-24)

| Decision | Choice |
|---|---|
| Scope | Glass chrome only: tab bar, top bars, sheets, **+** button, scroll-edge fade. The wider iOS pass is a later project. |
| Colours | Icons and labels in the bars keep the colours they have today. Glass changes the material, not the colours. |
| Approach | Swap at the shared seams (`HomeShell`, `GlobalAppbar`, `AppSheetChrome`, `AppScaffold`), keeping their APIs. Edit screens only where needed so content can run under the bars. |
| Branch | Same branch `feat/mobile-ios-polish`, same worktree. No new branch or worktree. |

## Current structure (verified 2026-09-24)

- **`HomeShell`** (`lib/core/app_routes/home_shell.dart`)
  - An `IndexedStack` of `SessionsScreen`, `PullRequestsScreen` and `SettingsScreen` (L47-53).
  - A Material `BottomNavigationBar` inside a `DecoratedBox` and `SafeArea` (L55-86).
  - Tapping the selected tab animates that tab's `ScrollController` to 0 (L62-74).
- **`GlobalAppbar`** (`lib/core/widgets/main_widgets/global_appbar.dart`)
  - Constructors: `.main` (left title) and `.sub` (centred title, back button with optional `leadingText`).
  - Parameters: `leading, title, titleText, actions, backgroundColor, centerTitle, elevation, leadingWidth, surfaceTintColor, bottom, hasBorder, leadingText, onAppPopIconPressed, systemOverlayStyle`.
  - Builds a Material `AppBar` with a `bgSurface` background (L69-94).
  - `preferredSize` is 56 plus the height of `bottom` (L109-110).
- **`AppScaffold`** (`lib/core/widgets/main_widgets/app_scaffold.dart`)
  - Already exposes `extendBody` and `extendBodyBehindAppBar` (both default false).
  - Its body is `Column > Expanded > Padding`.
- **Tab roots bypass `AppScaffold`**
  - Each builds a raw `Scaffold` with `GlobalAppbar.main`:
    - `sessions_screen.dart:22`
    - `pull_requests_screen.dart:15`
    - `settings_screen.dart:19`
  - Their lists use fixed padding and ignore `MediaQuery`:
    - `sessions_body.dart:148`, with bottom 40
    - `pull_requests_body.dart:65`
    - `settings_body.dart:152`
- **Pushed routes on `AppScaffold` with `GlobalAppbar.sub`**
  - manual connect, pairing scan, notifications (with actions), usage, preview (with actions), spawn, and the error routes.
  - `session_route_screen.dart:140` and `subagent_screen.dart:27` use a raw `Scaffold` with `GlobalAppbar.sub`.
  - Fixed-padding lists: `notifications_body.dart:88` and `usage_screen.dart:134`.
- **No app bar**
  - onboarding
  - connections
  - terminal: its chrome is `TerminalChatHeader` inside `TerminalBody`.
- **`AppSheetChrome`** (`lib/core/widgets/main_widgets/app_sheet_chrome.dart`)
  - It is a `bgSurface` `Material` with top corners, a grabber and padding.
  - It has 6 call sites, all shown through `showExpressiveSheet`:
    - the project, Claude account, agent and theme pickers
    - rename desktop
    - the connection menu
- **One FAB**: `sessions_screen.dart:31-37`, an accent circle that pushes `RoutesStrings.spawn`.

## Scope

### 1. Bottom bar: `HomeShell`

- **Replace the bar.** The Material `BottomNavigationBar` becomes `GlassTabBar`.
  - Items: Agents, PRs and Settings, with today's icons and labels.
  - Placement: floating, horizontally inset by `GlassMetrics.tabBarSideInset`, sitting `GlassMetrics.tabBarBottomInset` above the bottom safe area edge.
- **Tap behaviour.** `onSelected` keeps today's semantics. The same tab scrolls its controller to 0; another tab switches `selectedTab`.
  - `GlassTabBar` already fires on every tap, including the selected tab (project 1 Review Focus).
- **Layout.** The shell body extends under the bar, and a bottom `ScrollEdgeEffect` sits beneath the bar.
- **Bottom inset.** The shell provides it through `MediaQuery.padding.bottom`, so each tab's list can clear the bar. It equals the tab bar height plus its bottom inset plus the safe-area bottom.
- **Kept as is.** The shell's `IndexedStack` and per-tab `ScrollController`s do not change.

### 2. Top bars: `GlobalAppbar`

- **Same public API** and both constructors, so no call site changes its arguments.
- **Build.** It renders a transparent bar laid out like `GlassToolbar`. Inside one `GlassScope`:
  - The leading back button, or a custom `leading`, sits on a glass circle.
  - Each action sits on its own glass circle (icon widgets) or capsule (text widgets).
  - The title keeps its current style and alignment: `.main` left, `.sub` centred.
- **Colours.** The icons, labels and `leadingText` inside the glass keep the colours they have today. Glass supplies only the material behind them.
- **Wrapping actions.** Actions are arbitrary widgets from the screens. The bar wraps each one in a glass surface without rebuilding it.
- **Buttons with their own backgrounds.** An action that already paints its own filled background is placed on glass as is; its background is not stripped.
- **Unchanged parameters.** `backgroundColor`, `elevation` and `surfaceTintColor` are still accepted. They apply only when a screen explicitly asks for an opaque bar.
- **Dropped under glass.** `hasBorder` draws nothing under glass.
- **`bottom:` widgets** (for example tab strips) render below the glass row on the scrolled-under content. They are not glass.
- **Scroll-edge fade.** A top `ScrollEdgeEffect` sits under the bar.
- **Size.** `preferredSize` stays a height screens can rely on: toolbar row plus top gap, plus `bottom`.

### 3. Content under the bars

- **Tab roots.** Sessions, PRs and Settings set `extendBodyBehindAppBar: true`.
  - Their list padding adds `MediaQuery.paddingOf(context).top` (which then includes the bar) and the shell's bottom inset from item 1.
  - Their `RefreshIndicator` sets `edgeOffset` to the same top inset, so the spinner appears below the glass.
- **Pushed routes.**
  - `AppScaffold` routes set `extendBodyBehindAppBar: true`.
  - Notifications and usage fix their fixed list paddings the same way.
  - Screens whose body is a `SingleChildScrollView`, a camera view or a web view keep their content below the bar with a top padding equal to the bar inset. They stay readable, and their content does not need to scroll under the glass.
- **Raw-`Scaffold` routes.** `session_route_screen` and `subagent_screen` get the same flags and paddings.

### 4. Sheets: `AppSheetChrome`

- **Chrome.** `AppSheetChrome` keeps its API (`child`, `padding`) and renders `GlassSheetChrome`:
  - floating inset glass at partial height
  - opaque and edge-anchored near full height
  - the child and its padding inside
- **Barrier.** The sheets' barrier uses `GlassSheetLogic.barrierColor(skin)` (the fitted dim). The 6 call sites pass it through `showExpressiveSheet`'s `barrierColor`, or a shared helper does so.
- **Unchanged behaviour.** Result values, dismissal and keyboard insets are unchanged.

### 5. The **+** button

- `SessionsScreen`'s Material FAB becomes `GlassButton.icon(prominent: true)`:
  - accent glass
  - `onGlassProminent` icon
  - the same `onPressed`
- It sits `GlassMetrics.primaryButtonInset` from the right edge and `GlassMetrics.primaryButtonBottomGap` above the tab bar.

### 6. Left unchanged in this project

- **`TerminalChatHeader` and the terminal screen.** The terminal header is in another session's uncommitted work (`terminal_chat_header.dart`), as are `session_card.dart`, `block_card.dart` and `block_list.dart`. None of these files is edited. The terminal header gets glass after that work lands.
- **Onboarding and connections.** They have no app bar.
- **Cards, lists, chips and all content.**

## Behaviour that must not change

- Tab switching preserves each tab's scroll position, and `IndexedStack` stays.
- Tapping the selected tab scrolls it to top exactly once per tap.
- Back navigation, `onAppPopIconPressed` and its haptic work as before.
- Pull-to-refresh works on every list, with the spinner visible below the glass.
- Every sheet returns the same result and dismisses the same way.
- **+** opens spawn.

## Edge cases

- **Keyboard.** Screens with text input keep `resizeToAvoidBottomInset`: manual connect, spawn, and the rename sheet. The floating tab bar appears only on tab roots, which have no text input.
- **Large text.** The glass bars already clamp their text scale, and titles ellipsize. A title never overlaps the bar's buttons.
- **Accessibility settings.** Reduce Motion and Increase Contrast come from the engine.
- **Theme.** Light and dark, and switching between them while running, are covered by the engine's no-remount behaviour.
- **Near-full sheets.** Content state survives the floating-to-anchored switch.
- **Android.** It must compile. It renders the renderer's fallback and is not tuned.

## Testing

- **New widget tests**
  - `HomeShell`:
    - renders `GlassTabBar`, not `BottomNavigationBar`
    - selecting a tab switches the stack
    - tapping the selected tab animates its controller to 0 once
  - `GlobalAppbar`:
    - `.sub` renders the back button inside a glass surface and calls `onAppPopIconPressed`
    - actions render inside glass
    - `.main` title alignment is unchanged
  - Content inset:
    - on a tab root, the first list item's top edge is at or below the bar's bottom edge
    - the last item can scroll clear of the tab bar
  - `AppSheetChrome`: floats as glass at partial height, and passes its child through.
  - Sessions **+**: renders a prominent `GlassButton` that pushes spawn.
- **Existing tests.** They pass unchanged, except tests that assert the old Material widgets, such as `BottomNavigationBar` and the `AppBar` background colour. Those are updated to the new widgets, each change is named in the commit, and no assertion's intent is weakened.
- **Gate.** From `packages/mobile`, `flutter analyze` prints `No issues found!` and the full `flutter test` passes.
- **Real-app verification** runs on the paired app on the iPhone 17 Pro simulator, iOS 26.5:
  - screenshots in light and dark of Agents, PRs, Settings, Notifications, one pushed `.sub` screen (Usage) and one sheet (Theme picker)
  - a scroll showing content moving under the top and bottom glass
  - each screenshot inspected and sent to the user

## Out of scope

- Cupertino routes and swipe-back, large titles, action sheets and context menus, iOS controls, SF-style icons, and the haptics map. These form the follow-up iOS-pass project.
- Glass on the terminal header, cards or content.
- Tab-bar minimise-on-scroll.
- Android tuning.

## Risks

- **Content hidden under the bars.** Any list missed by the padding work renders its first or last row under the glass. The inset widget tests cover the tab roots. The screenshot pass covers the pushed screens.
- **Performance.** Every tab root now scrolls content under two glass layers. The simulator does not measure GPU cost faithfully, and frame timing on a physical iPhone is not known.
- **The other session's work.** When `session_card`, `block_card` and `terminal_chat_header` land on `development`, this branch must merge them. The glass work leaves those files alone, so the merge should be clean.
