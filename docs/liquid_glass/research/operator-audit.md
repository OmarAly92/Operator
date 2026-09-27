# Operator mobile — Liquid Glass component audit

Scope: `packages/mobile/lib` and `packages/mobile/packages` only. Read-only research, no edits made.
All paths below are relative to `/Users/omaraly/development/AI/Operator/packages/mobile/` unless given in full.

---

## 1. The glass layer (`lib/core/widgets/glass/`, `sheet/app_sheet.dart`, vendored `liquid_glass_renderer`)

### Foundation

- **`glass_metrics.dart`** — `GlassMetrics`: sealed class of layout constants shared by every glass surface (hit target 44, tab bar height 62, sheet corner radius 64−8, etc). No rendering, pure numbers.
- **`glass_style.dart`** — `GlassStyle`: resolves an `AppSkin` + `GlassVariant` (`regular`, `clear`, `prominent`, `chrome`) + size into a `LiquidGlassSettings` (tint, thickness, blur, chromatic aberration, light angle/intensity, saturation, fill ratio) and a `shadows()` list. This is the one place that turns "light/dark skin + size + variant" into concrete glass parameters — everything else consumes it.
- **`glass_scope.dart`** — `GlassScope`: thin wrapper around vendored `LiquidGlassLayer`, feeding it `GlassStyle.resolve(...)`. Used to open a glass "layer" (a region where sibling `LiquidGlass.grouped` shapes blend/merge) — used by `GlassToolbar` and `GlobalAppbar`.
- **`glass_surface.dart`** — `GlassSurface`: the core visual primitive. Takes a `GlassShapeKind` (`capsule`, `circle`, `rect`, `roundedRect`), a size/radius, a `GlassVariant`, `grouped`/`pressable`/`enabled` flags. Renders via vendored `LiquidGlass.auto`/`.grouped`/`.withOwnLayer` depending on variant/grouping, with an optional rim border (`skin.glassRim`) and a `GlassGlow` overlay when pressable. Motion: `_PressLift` — `AnimatedScale` to `1.08x` on pointer-down/up using `AppMotion.slow`/`spring` (a genuine spring press response, not a fixed-duration curve).
- **`glass_bar_item.dart`** — `GlassBarItem`: wraps an arbitrary child (icon button, text) in a `GlassSurface` capsule sized to `GlassMetrics.hitTarget`; used for icon buttons dropped into a `GlassScope`d bar (leading/trailing slots of `GlobalAppbar`). No own motion beyond the surface's press-lift.
- **`glass_button.dart`** — `GlassButton`: two named constructors, `.icon` and `.label`. Renders a `GlassSurface` (circle for icon-only, capsule for labelled) with `prominent`/`chrome`/`compact` variants, haptic on tap (`Haptics.tap` by default, overridable). This is the app's single "glass button" component — the equivalent of a Liquid Glass `Button`.
- **`glass_tab_bar.dart` + `glass_tab_bar_logic.dart`** — `GlassTabBar`/`GlassTabItem`: the bottom tab bar. A floating capsule bar with a "droplet" selection indicator that follows touch-drag in real time, lifts into a `GlassLens` (refractive lens shader) while dragging, and settles back into a flat tinted pill via critically-damped spring physics (`GlassTabBarLogic.springStep`, custom analytic spring integrator at 240 Hz) when released. Squash/stretch on the droplet is speed-dependent. This is the most elaborate motion in the whole glass layer — a genuine "liquid" tab bar, closest to Apple's morphing-pill tab bar.
- **`glass_lens.dart`** — `GlassLens`: a `LeafRenderObjectWidget` that loads `shaders/tab_lens.frag` (a fragment shader, falls back to a plain stroked rim if shaders are unsupported) and paints a magnifying/refractive lens via `BackdropFilterLayer` with a custom shader. Used only inside `GlassTabBar`'s lifted state.
- **`frosted_header.dart`** — `FrostedMaterial` (blur+saturate `ImageFilter`), `FrostedBand` (a scroll-under blur band with an optional hairline, used as a sheet header background that fades in as content scrolls under it), `FrostedCircleButton` and `FrostedCapsule` (frosted-blur circular/capsule buttons, distinct from `GlassSurface` — these use a plain `BackdropFilter` blur rather than the liquid-glass shader, i.e. a cheaper "frosted" look used specifically inside `AppSheet`'s header for back/close buttons and trailing actions).
- **`glass_sheet.dart`** — `GlassSheetLogic` (floating-vs-anchored detent math, corner radius, barrier color) + `GlassSheetChrome` (wraps arbitrary sheet content: floating rounded-rect glass card if short, anchored bottom sheet with `bgSurface` if tall) + `showGlassSheet()` helper (calls vendored `showExpressiveSheet` with `GlassSheetChrome`). **Only consumer of `showGlassSheet`/`GlassSheetChrome` outside its own file is the debug-only `glass_lab_screen.dart`** — production code uses `AppSheet` instead (below), which reimplements similar detent logic inline rather than reusing `GlassSheetChrome`.
- **`glass_toolbar.dart`** — `GlassToolbar`: a simple fixed top toolbar (leading/title/trailing `NavigationToolbar`) inside a `GlassScope`. Distinct from `GlobalAppbar` (below) — appears unused outside the glass lab scene; production top bars go through `GlobalAppbar`.
- **`scroll_edge_effect.dart`** — `ScrollEdgeEffect`/`ScrollEdge`: a top/bottom edge-blur-fade effect (shader `shaders/scroll_edge_blur.frag`, with a `BackdropFilter`+gradient fallback) that increases blur/tint as content scrolls under a bar. Not glass per se, but the effect that makes bars look like they're "over" scrolling content.
- **`scroll_under_bars.dart`** — `ScrollUnderBars`: wraps a scrollable body + a top `ScrollEdgeEffect`, driven by scroll notifications. Used by `AppScaffold` when `scrollsUnderAppBar: true`.
- **`lib/core/widgets/glass/lab/`** (`glass_lab_backdrop.dart`, `glass_lab_scene.dart`, `glass_lab_screen.dart`) — a **debug-only visual test harness** (route `/glass-lab`, gated `kDebugMode`, driven by a `GLASS_LAB_SCENE` env var) that stages `GlassTabBar`, `GlassToolbar`, `GlassButton`, `AppSheet`/`GlassSheetChrome`, and `ScrollEdgeEffect` over a striped/colored backdrop for visual regression screenshots. Not part of the real navigation graph.

### `lib/core/widgets/sheet/app_sheet.dart`

`AppSheet` is the app's real bottom-sheet system (distinct from, and more elaborate than, `glass_sheet.dart`'s `GlassSheetChrome`): a multi-page, glass-chromed modal sheet with:
- `AppSheetPage`/`AppSheetController` (`push`/`pop`/`close`) — an internal navigation stack of pages inside one sheet.
- Detents: `fit` (content height), `medium` (55% screen), `large` (92% screen).
- Chrome: `FrostedBand` header that fades in on scroll, `FrostedCircleButton` back/close, `FrostedCapsule`-wrapped trailing actions, a `GlassSurface` capsule search field (`_SearchCapsule`) that fades in/out with scroll position.
- Motion: page-push/pop uses `AnimationController`s driven by `AppMotion.sheetPush`/`sheetPushCurve` with a parallax "covered" page (translated + fractionally faded), plus a header-visibility "handoff" animation between pages so the frosted band doesn't jump.
- `showAppSheet()` is the call site API; it wraps `AppSheet` in vendored `showExpressiveSheet`.

### Vendored `liquid_glass_renderer` (`packages/liquid_glass_renderer/lib`)

The actual rendering engine glass surfaces sit on top of:
- `LiquidGlass` (`.auto`, `.grouped`, `.withOwnLayer`) — the widget that paints a shape with the liquid-glass shader.
- `LiquidGlassLayer` (`rendering/liquid_glass_layer.dart`) — groups sibling glass shapes so they visually blend/merge at proximity (the "liquid" merging effect), backed by `LiquidGlassRenderObject`.
- `LiquidGlassSettings` — tint/thickness/blur/chromatic-aberration/light/ambient/refractive-index/saturation/fill-ratio data class (what `GlassStyle.resolve` produces).
- `LiquidShape`/`liquid_shape.dart` — shape primitives: `LiquidRoundedRectangle`, `LiquidOval`, `LiquidRoundedSuperellipse`.
- `GlassGlow`/`GlassGlowLayer` (`glass_glow.dart`) — the white glow overlay `GlassSurface` adds when `pressable`.
- `GlassShadow` (`glass_shadow.dart`), `FakeGlass` (`fake_glass.dart` — a cheaper non-shader fallback), `LiquidGlassBlendGroup`, `LiquidStretch`/`RawLiquidStretch`/`OffsetResistanceExtension` (`stretch.dart` — drag-resistance physics, not currently wired into any app widget found).
- Shaders live in `packages/liquid_glass_renderer/lib/assets/shaders/*.frag`/`.glsl` (geometry blending, final render composite, fake-glass color, SDF, displacement encoding).

This package is a general-purpose Flutter Liquid Glass engine (not Operator-specific) — `GlassStyle`/`GlassSurface`/etc. are the Operator-specific adaptation layer on top of it.

### Other vendored "expressive" UI packages (`packages/liquid_glass_renderer` siblings)

| Package | What it is | Used from |
|---|---|---|
| `expressive_sheet` | `showExpressiveSheet`/`ExpressiveSheetRoute` — a spring-physics (Material `motor` package) bottom-sheet route: drag-to-dismiss carries fling velocity into the close spring, expressive-spatial enter / fast-standard exit motion curves. | `glass_sheet.dart`, `sheet/app_sheet.dart`, `glass_lab_screen.dart` — i.e. it is the transport under **every** app sheet (both `showGlassSheet` and `showAppSheet`). |
| `expressive_snack` | `showExpressiveSnack`/`clearExpressiveSnacks` — Material 3 Expressive floating, stacked, spring-driven snackbar pills (`snack.dart`, `snack_view.dart`, `snack_stack.dart`, `snack_overlay.dart`). | Only `lib/core/widgets/main_widgets/app_toast.dart` (`AppToast.show`). |
| `expressive_loading_indicator` | `LoadingIndicator` (+ `.contained`, `.determinate`, `.containedDeterminate`) — Material 3 Expressive shape-morphing spinner (circle → soft-burst → cookie → pentagon → pill → sunny → …), built on `material_shapes`' `RoundedPolygon`/`Morph`. | `lib/core/widgets/loading_widget/app_loader.dart` (`AppExpressiveLoader`), and internally by `expressive_refresh_indicator`. |
| `expressive_refresh_indicator` | `ExpressiveRefreshIndicator` — a full Material-3-Expressive "pull to refresh" (determinate shape-morph while pulling, crossfades to the indeterminate spinner while refreshing, spring-settles). | **Not imported anywhere in `lib/`.** Fully built, fully unused — see §4. |
| `material_shapes` | `RoundedPolygon`, `Morph`, `MaterialShapes` (named polygon presets), `MaterialShapeBorder` — the shape-morphing math underneath the expressive loading indicator. | Only transitively via `expressive_loading_indicator`; no direct import in `lib/`. |

---

## 2 & 3. Screens, chrome, and the component matrix

### Routes (`lib/core/app_routes/routes_strings.dart`, `app_router.dart`)

All routes go through `AppRouter.generateRoute` and are **`MaterialPageRoute`** (platform-adaptive push transition; iOS gets the native slide-cover via Flutter's platform theme, but there is no bespoke Liquid-Glass push/zoom transition anywhere — `app_router.dart:45-213`). `spawn` is the only `fullscreenDialog: true` route (`app_router.dart:101`, modal up-transition). No `Hero`, no custom `PageRouteBuilder`, no shared-element transitions found anywhere in `lib/`.

Routes: `/onboarding`, `/pair`, `/pair/manual`, `/connections`, `/sessions` (→ `HomeShell`), `/session`, `/session/agent` (subagent), `/spawn`, `/terminal`, `/notifications`, `/preview`, `/usage`, `/glass-lab` (debug only).

### Home shell (`lib/core/app_routes/home_shell.dart`)

Fully glass: `IndexedStack` of Sessions/PRs/Settings tabs, a floating `GlassTabBar` (`home_shell.dart:162`) + a `GlassButton.icon` spawn FAB with `chrome: true` styling (`home_shell.dart:192`), a bottom `ScrollEdgeEffect` (`home_shell.dart:147`), and `AppToast` for the offline-spawn message (`home_shell.dart:202`). No `AppBar`/`Scaffold.bottomNavigationBar` — the tab bar and FAB are hand-positioned `Positioned` widgets over a plain `Scaffold`.

### The two "workhorse" bars: `GlobalAppbar` and `AppScaffold`

- `lib/core/widgets/main_widgets/global_appbar.dart` — `GlobalAppbar.main`/`.sub`: **already fully glass** (`GlassScope` + `NavigationToolbar` + `GlassBarItem`-wrapped leading/trailing, `global_appbar.dart:110`). This is the standard top bar for almost every pushed screen:
  - `subagent_screen.dart:29`, `notifications_screen.dart:24`, `manual_connect_screen.dart:37`, `pairing_scan_screen.dart:44`, `preview_screen.dart:18`, `pull_requests_screen.dart:20`, `session_route_screen.dart:146`, `sessions_screen.dart:24`, `settings_screen.dart:23`, `spawn_screen.dart:11`, `usage_screen.dart:30`.
  - Exceptions: `onboarding_screen.dart` and `connections_screen.dart` have **no app bar at all** (raw `AppScaffold(body: ...)`); `terminal_screen.dart` uses its own custom header (`TerminalChatHeader`) instead of `GlobalAppbar`; `blocks` has no top-level screen file (it's embedded inside the terminal route).
- `lib/core/widgets/main_widgets/app_scaffold.dart` — thin wrapper over Material `Scaffold`; optionally wires `ScrollUnderBars` when `scrollsUnderAppBar: true`.
- Fallback/error route (`app_router.dart:200`, `:211`) renders `AppScaffold(appBar: GlobalAppbar.sub(), body: AppErrorWidget())` — still glass, just a generic error page.

### `TerminalChatHeader` (`lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart`)

Bespoke glass header for the terminal/chat screen: `GlassScope` + `FrostedBand` (scroll-under blur) + `GlassButton`s, showing back button, session activity/working indicator, and (via `terminal_preview_globe.dart`) a live-preview affordance. Not built on `GlobalAppbar`.

### Composer (`terminal_composer.dart`, and its satellites)

`TerminalComposer` is a `GlassSurface`-backed capsule/card (`terminal_composer.dart:276`, `:380`, radius animates between a resting capsule and an expanded rounded card, `cardRadius = 26`). Its satellites:
- `composer_add_button.dart` (+ button opening `add_context_sheet.dart`, a glass `AppSheet`),
- `composer_model_chip.dart` (custom pill chip, opaque — not `GlassSurface`),
- `composer_attachment_tray.dart` (opaque thumbnail tray, `skin.bgSurface`-style, no glass),
- `slash_command_menu.dart` (glass — `GlassSurface(kind: rect, size: 400 …)`, `slash_command_menu.dart:29`),
- `mic_key.dart` (dictation mic button — **opaque** colored circle, not glass, `mic_key.dart:132`),
- `voice_strip.dart` ("Listening…" pill — **glass**, `GlassSurface` capsule, `voice_strip.dart:35`),
- `permission_mode_page.dart` (`PermissionModeRow`/`PermissionModeList`, pushed into the glass `AppSheet` via `AppSheet.of(context).push(...)`, but the row content itself is the opaque `SettingsGroup`/`SettingsRow` — see below).

### Sessions board (`lib/feature/sessions/presentation/sessions_screen`)

- `sessions_screen.dart:24` — `GlobalAppbar.main`.
- `sessions_body.dart:145` — plain Material **`RefreshIndicator`** (pull-to-refresh) — not the vendored `ExpressiveRefreshIndicator`.
- `sessions_body.dart:159` — `SessionFilterChipsRow` → `AppPill` (`lib/core/widgets/main_widgets/app_pill.dart`) — opaque filter-chip/segmented-control equivalent, tinted-active state, no glass version.
- `session_card.dart` — opaque `AppContainer` card (`session_card.dart:59`) with a `StatusDot` (`lib/core/widgets/main_widgets/status_dot.dart`, breathing-opacity animated colored dot) inside a tinted status pill (`session_card.dart:91-117`), plus `_MetaChip` pill badges for harness/account/model (`session_card.dart:126-133`). All opaque.
- `board_skeleton.dart` — shimmer-bar loading skeleton (`lib/core/widgets/motion/shimmer.dart`), opaque `Container` bars, no glass, no `AppExpressiveLoader`.
- `session_actions_sheet.dart:14` — **plain Material `showModalBottomSheet`** (no `shape`/`backgroundColor` override at all — a fully default, opaque Material sheet), containing `ListTile`s and an `AppDialog.confirm` (`session_actions_sheet.dart:55`) for the destructive Kill confirmation.
- `session_route_screen.dart:146` — glass `GlobalAppbar.sub`, generic loading/redirect screen while the terminal route resolves.

### Pull requests (`lib/feature/pull_request`)

- `pull_requests_screen.dart:20` — `GlobalAppbar.main`.
- `pull_requests_body.dart:62` — plain Material `RefreshIndicator`.
- `pr_card.dart` — opaque `AppContainer` card, custom entrance animation (`AnimationController`/`_entrance`), lifecycle-label pill via `Tone`/`AppConstants` colors — no glass.

### Notifications (`lib/feature/notification`)

- `notifications_screen.dart:24` — `GlobalAppbar.sub`.
- `notifications_body.dart:81` — plain Material `RefreshIndicator`.
- `notification_bell.dart:24-38` — Material `IconButton` + a plain colored-circle unread-count **badge** (opaque `Container`/`BoxDecoration`, not glass) — this is the app's only numeric badge.
- `notification_row.dart` — opaque row (not inspected line-by-line but confirmed non-glass by the sweep in §4).

### Settings (`lib/feature/settings`)

- `settings_screen.dart:23` — `GlobalAppbar.main`.
- `settings_body.dart` — built entirely from `SettingsGroup`/`SettingsRow`/`SettingsToggle` (`lib/core/widgets/main_widgets/settings_group.dart`) — an opaque card list (`bgSurface` + `borderDefault`, `settings_group.dart:38-46`) with plain Material `Switch` (`settings_group.dart:170`), plain `CircularProgressIndicator`/`AppLoader` busy-states, and chevron-right affordances for navigation rows. This is the single biggest "list of options" chrome pattern in the app and it is 100% non-glass.
- `settings_body.dart:93` — `AppDialog.confirm` for a destructive settings action.
- `phone_alerts_group.dart`, `test_connection_row.dart` — same `SettingsGroup`/`SettingsRow` pattern.

### Spawn (`lib/feature/spawn`)

- `spawn_screen.dart:11` — `GlobalAppbar.sub` (`fullscreenDialog: true` route).
- `spawn_body.dart` — form-like screen: `Switch` at `spawn_body.dart:139` (also `SettingsGroup`/`SettingsRow` pattern via `spawn_option_rows.dart`), a Material `SnackBar` via `ScaffoldMessenger` at `spawn_body.dart:91-99` (note: **not** `AppToast` — inconsistent with the rest of the app), and `spawn_options_sheet.dart` which opens a glass `AppSheet` (`showAppSheet<...>`) containing more `SettingsRow`s.

### Pairing (`lib/feature/pairing`)

- `onboarding_screen.dart` — no app bar; a `GlassButton.icon` back button when reached from "Desktops" (`onboarding_screen.dart:47-52`), `PrimaryButton` (opaque `ElevatedButton`, see §4) for the main CTA.
- `pairing_scan_screen.dart:44` — `GlobalAppbar.sub`; body is a live camera view (`mobile_scanner` package `MobileScannerController`, `pairing_scan_body.dart:22`) with `CameraPermissionGate` (opaque, `PrimaryButton` "Open Settings") and `connection_failure_banner.dart` (opaque banner) overlays. No custom glass viewfinder chrome around the scanner.
- `manual_connect_screen.dart:37` — `GlobalAppbar.sub`; `manual_connect_body.dart:46` has a plain Material `Switch` ("secure" toggle) and `TextField`s, all opaque form styling.
- `connections_screen.dart` — no app bar (`connections_screen.dart:29`); `connections_body.dart`/`connections_header.dart`/`connection_row.dart` all opaque; `connection_menu_sheet.dart` opens a **glass** `AppSheet` (`showAppSheet<ConnectionMenuResult>`); `remove_connection_dialog.dart` calls `AppDialog.confirm` (opaque dialog, see §4); `desktop_switcher_sheet.dart` and `re_pair_sheet.dart` both open glass `AppSheet`s.

### Blocks / chat transcript (`lib/feature/blocks`, embedded in the terminal route)

- `blocks_body.dart` — the message list; opaque throughout (`block_card.dart`, `block_list.dart`, `block_markdown.dart`, `block_question_options.dart`, `block_result_section.dart`, `block_status_dot.dart`, `block_todo_list.dart`, `incoming_response.dart`, `message_meta_row.dart`, `running_tasks_bubble.dart`, `sticky_block_header.dart`, `thinking_row.dart`, `tool_group_header.dart`, `turn_fold_row.dart`, `turn_group_status.dart`, `context_readout_chip.dart` — none import any glass widget).
- `block_find_bar.dart:38-43` — an opaque, docked "find in blocks" search bar (`skin.bgChrome` + bottom border), a `TextField` with prev/next/filter controls — **not** glass, unlike `AppSheet`'s glass `_SearchCapsule`.
- `block_selection_bar.dart` — text-selection action bar (Copy), opaque, calls `context.showSnackBar('Copied')` (plain Material `SnackBar`, not `AppToast`).
- `block_action_sheet.dart:29` and `model_picker_sheet.dart:28` — both call **plain Material `showModalBottomSheet`** with a manually-matched `backgroundColor: context.skin.bgSurface` + rounded-top `shape` (i.e. they *approximate* the app's sheet look by hand, but are a different code path from `AppSheet`/glass, and don't get the frosted header, drag-spring, or search-fade behavior).
- `background_tasks_sheet.dart` — opens a glass `AppSheet` (`showAppSheet<...>`).
- `floating_working_control.dart:1-50` — **glass** (`GlassButton`+`GlassSurface`), a floating pill above the composer showing "Agent working…" / jump-to-latest, with shimmer + spring motion.

### Terminal chrome besides the composer/header

- `terminal_status_bar.dart`, `terminal_key_row.dart` (control-key row above the keyboard), `terminal_dead_overlay.dart:22-26` (opaque red-tinted "agent stopped" banner) — all opaque.
- `raw_terminal_pane.dart`/`terminal_surface.dart` embed the separate `packages/terminal` renderer, which per `TERMINAL.md`/`CLAUDE.md` keeps its own palette and is out of scope for this glass audit.
- `suggested_prompt_bubble.dart`, `terminal_composer_draft_hint.dart` — opaque bubbles.

### Subagent screen (`lib/feature/blocks/presentation/subagent_screen/ui/subagent_screen.dart`)

`GlobalAppbar.sub` (`subagent_screen.dart:29`) + reuses the same opaque `blocks_body.dart` transcript widgets.

### Preview (`lib/feature/preview`)

`preview_screen.dart` — `GlobalAppbar.sub` with a plain `IconButton` refresh action (`preview_screen.dart:22-26`); body is a `webview_flutter` `WebViewWidget` (`preview_browser.dart:58-61`) with no custom chrome (no address bar, no share/open-in-Safari action) around the web content.

### Usage (`lib/feature/usage`)

`usage_screen.dart:30` — `GlobalAppbar.sub`; `quota_section.dart` — opaque `Container` card (`quota_section.dart:28-34`) with plain Material `LinearProgressIndicator` bars (`quota_section.dart:96-101`) for quota readouts. No chart widget, no glass, no expressive/morphing indicator reuse here despite one being available in the vendored packages.

### Onboarding

Already covered above — no app bar, `PrimaryButton` CTA, `GlassButton.icon` back affordance only when entered from the desktop switcher.

### Dictation (`lib/feature/dictation`)

`mic_key.dart` (opaque mic button, used at two sizes/variants: composer inline + "prominent") and `voice_strip.dart` (glass "Listening…" capsule) are the only presentation widgets; no dedicated screen/route.

---

## The matrix

Rows = component kind. "Glass version in our layer" names the class if one exists. "Used where" gives a count of files/screens using that *kind* and 1–2 key files. "Currently implemented with" is the dominant implementation for the *majority* of instances of that kind today.

| Component kind | Glass version exists? | Used where (count · key files) | Currently implemented with |
|---|---|---|---|
| Top bar / nav bar | **Yes** — `GlobalAppbar` (`global_appbar.dart`), `GlassToolbar` (lab only) | 11 screens · `global_appbar.dart:110`, e.g. `settings_screen.dart:23` | Custom glass (`GlassScope`+`NavigationToolbar`) |
| Chat/terminal header | **Yes** — `TerminalChatHeader` (bespoke) | 1 · `terminal_chat_header.dart` | Custom glass (`GlassScope`+`FrostedBand`) |
| Tab bar (bottom nav) | **Yes** — `GlassTabBar` | 1 · `home_shell.dart:162` | Custom glass, liquid-lens motion |
| Primary action button (icon/label) | **Yes** — `GlassButton` | ~10+ call sites · `home_shell.dart:192`, `terminal_composer.dart` | Custom glass |
| Secondary/CTA button (forms) | No | 5 · `primary_button.dart` used in onboarding, connections, camera gate, preview | Opaque `ElevatedButton` (`PrimaryButton`) + `flutter_spinkit` spinner |
| Bottom sheet (structured, multi-page) | **Yes** — `AppSheet`/`showAppSheet` | 10 files · `re_pair_sheet.dart`, `connection_menu_sheet.dart`, `add_context_sheet.dart`, `spawn_options_sheet.dart`, `project_picker_sheet.dart`, `theme_picker_sheet.dart`, `background_tasks_sheet.dart`, `desktop_switcher_sheet.dart` | Glass (`AppSheet`, frosted header) |
| Bottom sheet (simple, single content) | Partial — `GlassSheetChrome`/`showGlassSheet` exists but is **only used by the debug lab screen** | 4 files use plain Material sheets instead: `model_picker_sheet.dart:28`, `block_action_sheet.dart:29`, `terminal_chat_header.dart:109`, `session_actions_sheet.dart:14` | Plain Material `showModalBottomSheet` (2 of 4 hand-style `backgroundColor`/`shape`; `session_actions_sheet.dart` has none at all) |
| Dialogs / confirmation | No | 4 call sites · `settings_body.dart:93`, `remove_connection_dialog.dart:5`, `terminal_body.dart:77`, `session_actions_sheet.dart:55` | Opaque custom `Dialog` (`AppDialog.confirm`, `app_dialog.dart:22`) — no blur/glass at all |
| Action sheet (list of actions) | No | 2 · `block_action_sheet.dart`, `session_actions_sheet.dart` | Plain Material `showModalBottomSheet` + `ListTile` |
| Menus / popups | N/A | 0 found | None — no `PopupMenuButton`/`MenuAnchor`/context menu anywhere in `lib/` |
| Search field | Partial — `AppSheet`'s `_SearchCapsule` is glass | 2 · `app_sheet.dart:704` (glass), `block_find_bar.dart:38` (not glass) | Mixed: glass inside sheets, opaque docked bar in blocks transcript |
| Segmented control / filter chips | No | 2 · `session_filter_chips_row.dart` (`AppPill`), pull-requests filter row | Opaque custom pill (`app_pill.dart`) |
| Switches / toggles | No | 3+ files · `settings_group.dart:170`, `manual_connect_body.dart:46`, `spawn_body.dart:139` | Plain Material `Switch` |
| Sliders | N/A | 0 found | None |
| Pickers (project/theme/model) | Mostly yes | `project_picker_sheet.dart`, `theme_picker_sheet.dart` → glass `AppSheet`; `model_picker_sheet.dart` → plain Material sheet | Mixed (2 glass, 1 opaque) |
| Chips / badges (status, meta) | No | `session_card.dart:91-133` (status pill + `_MetaChip`), `composer_model_chip.dart`, `context_readout_chip.dart`, `notification_bell.dart:31` (unread count) | Opaque tinted `Container`/`BoxDecoration`; `StatusDot` for the breathing dot |
| Text fields / composer | Partial — main composer card is glass | `TerminalComposer` (glass, `terminal_composer.dart:276`); `manual_connect_body.dart`, `block_find_bar.dart`, `app_text_field.dart` (opaque) | Mixed — 1 glass, rest opaque `TextField` |
| Snackbars / toasts | Partial — `AppToast` is a branded expressive-snack wrapper | `AppToast.show`: 2 direct + used by `home_shell.dart:202`, `slash_command_menu.dart`; but 11 files use plain `context.showSnackBar`/`ScaffoldMessenger` (`extensions.dart:4`) instead, e.g. `sessions_screen.dart:18-19`, `spawn_body.dart:98-99`, `block_action_sheet.dart:51` | Mostly plain Material `SnackBar`, some `AppToast` |
| Pull-to-refresh | No — vendored `ExpressiveRefreshIndicator` unused | 3 · `sessions_body.dart:145`, `pull_requests_body.dart:62`, `notifications_body.dart:81` | Plain Material `RefreshIndicator` |
| Loading indicators | Partial — `AppExpressiveLoader`/`LoadingIndicator` exists and is branded, but inconsistently adopted | `AppLoader`/`AppExpressiveLoader` (`app_loader.dart`), plus ad hoc `CircularProgressIndicator`, `CupertinoActivityIndicator` (`app_loader.dart:28`), `flutter_spinkit`'s `SpinKitThreeBounce` (`primary_button.dart:91,133`) | 4 different spinner implementations coexist |
| Loading skeletons | No | 1 · `board_skeleton.dart` | Opaque shimmer bars (`motion/shimmer.dart`) |
| Page transitions | No | All routes · `app_router.dart:45-213` | `MaterialPageRoute` (platform-adaptive default); no custom glass transition |
| Swipe actions | N/A | 0 found | None — no `Dismissible`/slidable anywhere |
| Camera / QR scan chrome | No | 1 · `pairing_scan_body.dart` (`mobile_scanner`) | Plain full-bleed camera view, opaque permission/error overlays, no glass viewfinder frame |
| Web content chrome | No | 1 · `preview_screen.dart`/`preview_browser.dart` | Plain `IconButton` refresh action in a `GlobalAppbar`; no browser-style chrome around the `WebView` |
| Settings/options list rows | No | Pervasive · `settings_group.dart` used by settings, spawn options, permission-mode sheet, phone alerts, test-connection row | Opaque card list (`SettingsGroup`/`SettingsRow`/`SettingsToggle`) |
| Progress bars (determinate) | No | 1 · `quota_section.dart:96-101` | Plain Material `LinearProgressIndicator` |
| Dictation mic control | Partial | `mic_key.dart` (opaque), `voice_strip.dart` (glass feedback pill) | Mixed |
| Cards (session/PR) | No | `session_card.dart`, `pr_card.dart` | Opaque `AppContainer` |
| Notification badge (count) | No | 1 · `notification_bell.dart:31-38` | Opaque colored circle |

---

## 4. Screens/surfaces that still look non-glass end to end

These are the places where, even though the surrounding bar may be glass, the *content* a user spends most time looking at has zero Liquid Glass material:

1. **Settings screen** (`settings_body.dart`) — entirely `SettingsGroup`/`SettingsRow`/`SettingsToggle` opaque cards; glass bar on top, opaque everything below.
2. **Spawn screen** (`spawn_body.dart`, `spawn_option_rows.dart`) — same opaque settings-row pattern; plain `ScaffoldMessenger`/`SnackBar` instead of `AppToast`.
3. **Sessions board cards & PR cards** (`session_card.dart`, `pr_card.dart`) — the single most-viewed content on the home tab is fully opaque; only the tab bar/FAB around it is glass.
4. **Notifications list** (`notifications_body.dart`, `notification_row.dart`, `notification_bell.dart`) — opaque rows, opaque badge, Material `RefreshIndicator`.
5. **Blocks/chat transcript** (all of `blocks_screen/ui/widgets/*` except `floating_working_control.dart` and `slash_command_menu.dart`) — the core chat content area is 100% opaque Material styling.
6. **Connections screen** (`connections_body.dart`, `connection_row.dart`, `connections_header.dart`) — no app bar and no glass at all; `PrimaryButton` (opaque `ElevatedButton`) for actions.
7. **Manual connect / pairing scan forms** — opaque `TextField`/`Switch` form rows; camera view has no glass viewfinder chrome.
8. **Confirmation dialogs everywhere** (`app_dialog.dart`) — a plain, unblurred `Dialog` card; this is the one surface type in the whole app with *no* glass variant at all, used for every destructive confirmation (kill session, remove connection, settings resets).
9. **Two of the four bottom sheets** (`model_picker_sheet.dart`, `session_actions_sheet.dart`) — plain `showModalBottomSheet`, one of them (`session_actions_sheet.dart`) with no styling override whatsoever (default Material grey sheet).
10. **Usage screen** (`quota_section.dart`) — opaque card + plain `LinearProgressIndicator`, despite a branded shape-morphing indicator already vendored and unused here.
11. **Preview (WebView) screen** — functional but chrome-less; a glass `GlobalAppbar` sits directly on top of a bare `WebViewWidget`.

---

## Notable dead/unused surfaces worth knowing about before designing the glass rollout

- `ExpressiveRefreshIndicator` (`packages/expressive_refresh_indicator`) is fully built, tested-looking, and **never imported** anywhere in `lib/` — all three pull-to-refresh call sites use the plain Material `RefreshIndicator` instead.
- `showGlassSheet`/`GlassSheetChrome` (`glass_sheet.dart`) is real glass-sheet chrome, but production code went a different route (`AppSheet`) and only the debug `glass_lab_screen.dart` still calls it — worth deciding whether to delete or reuse it for the "simple single-content sheet" gap identified above (item 9).
- `GlassToolbar` (`glass_toolbar.dart`) duplicates part of what `GlobalAppbar` does and is also lab-only.
- Loading indicators are fragmented across four implementations (`CircularProgressIndicator`, `CupertinoActivityIndicator`, `flutter_spinkit`'s `SpinKitThreeBounce`, and the branded `LoadingIndicator`/`AppExpressiveLoader`) with no single source of truth.
- Toasts are fragmented across `AppToast` (branded) and plain `context.showSnackBar`/`ScaffoldMessenger.showSnackBar` (`extensions.dart:4`), used in roughly a 1:5 ratio in favor of the plain version.
