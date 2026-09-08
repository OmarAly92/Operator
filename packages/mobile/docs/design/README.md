# Design system — docs/design/

Source: `docs/design/Operator Mobile - standalone.html`, a Pencil "bundled page" export
("Operator — mobile design sync"). Decoded once to
`/private/tmp/.../scratchpad/template.html` for extraction (that scratch path does not
persist — re-decode from the standalone HTML's `<script type="__bundler/template">` /
`<script type="__bundler/manifest">` payloads if you need to re-derive anything; see the
"How this was decoded" note at the bottom).

This is a **full re-skin** (explicit user decision, 2026-09-08): the prototype's warm
cream/paper + brand-green palette and Anthropic Sans typography fully replace the prior
blue Material look across the whole app, not just new screens.

## Layout

```
docs/design/
  README.md         this file
  colors.md          Phase 2 — AppSkin token tables, shadow recipes, judgment calls
  typography.md       Phase 3 — font families, AppTextStyle scale, licensing note
  motion.md           Phase 4 — durations, curves, keyframe recipes, press scales
  components.md        Phase 5 — core widget specs + which file implements each
  <screen>/
    <screen>.md         full visual spec + implementation brief, ONE file per screen
    *.png               headless screenshots (dark default; every state/sheet/dialog)
```

A screen's bottom sheets and dialogs are documented as subsections **inside** that
screen's own `<screen>.md` — never a separate file or directory. The agent that builds a
screen builds every sheet/dialog it opens in the same pass.

## Already implemented in this repo — do NOT re-invent

| Layer | File(s) |
|---|---|
| Skin | `lib/core/app_themes/colors/{app_skin,light_skin,dark_skin}.dart` — full prototype palette wired, see `colors.md` |
| Type | `lib/core/app_themes/text_style/app_text_style.dart` — `Anthropic Sans Text`/`Display`/`JetBrains Mono` wired, see `typography.md` |
| Motion | `lib/core/app_themes/app_motion.dart` (`AppMotion`) — durations/curves/keyframe deltas/press scales, see `motion.md` |
| Radius/spacing | `lib/core/utils/app_constants.dart` — evidence-derived radius scale, see `components.md` |
| Core widgets | `lib/core/widgets/**` — restyled buttons, containers, pills, text field, settings rows/toggle, dialog, empty state, bottom sheets (now built on the vendored `expressive_sheet`), plus new primitives `PressScale`, `AppExpressiveLoader` (vendored `expressive_loading_indicator`), `ShimmerBlock`, `StatusDot`, `TypingDots`, `AppToast` (vendored `expressive_snack`), `AppSheetChrome` — see `components.md` for the full spec-to-widget map |

Read `colors.md` → `typography.md` → `motion.md` → `components.md` before touching any
screen — every screen brief below assumes you've consumed these and will only reference
token/getter names, not raw hex/px/ms values.

## Screen → feature map (single source of truth for where UI is built)

The prototype models exactly 8 screens (verified by walking every `sc-if`/tab branch in
the decoded template — see "Screens NOT covered" below for what it does *not* model).

| # | Prototype screen (`sc-if` / tab) | Owning feature path | Notes |
|---|---|---|---|
| 1 | `isOnboarding` — "Connect your desktop" | `lib/feature/onboarding/presentation/onboarding_screen/` | Entry screen when no paired desktop exists. |
| 2 | `isConnections` — "Your desktops" list | `lib/feature/pairing/presentation/connections_screen/` **(new — does not exist yet)** | Pairing feature already has `pairing_scan_screen/` (QR) and `manual_connect_screen/` (add/edit form) — this saved-connections LIST screen is new UI; its add/edit sheet should reuse `manual_connect_screen`'s cubit/form logic rather than duplicating it, see the screen's own `.md` for how. |
| 3 | `tab0` — "Agents" board (Loading/Empty/Loaded) | `lib/feature/sessions/presentation/sessions_screen/` | First tab of the bottom-nav home shell (`lib/core/app_routes/home_shell.dart` — core, not owned by any feature). |
| 4 | `tab1` — "Orchestrator" | `lib/feature/orchestrator/presentation/orchestrator_screen/` | Second tab. |
| 5 | `tab2` — "Pull Requests" | `lib/feature/pull_request/presentation/pull_requests_screen/` | Third tab. |
| 6 | `tab3` — "Settings" | `lib/feature/settings/presentation/settings_screen/` | Fourth tab. |
| 7 | `isChat` — session detail (blocks/raw view, composer, command menu) | `lib/feature/blocks/presentation/blocks_screen/` (structured/blocks view) **and** `lib/feature/terminal/presentation/terminal_screen/` (raw view, header, composer shell), reached via `lib/feature/sessions/presentation/session_route/` | See the corrected assessment below — this is a good structural match, not a conflict. Split across two features; `session_detail.md` says which piece belongs to which. |
| 8 | `isSpawn` — "Spawn agent" | `lib/feature/spawn/presentation/spawn_screen/` | Opened from the Agents tab's empty state or a FAB; owned by `spawn`, not `sessions`, even though `sessions` launches it (launcher-vs-owner). |

**Screen 7 — corrected assessment (was previously flagged as a hard conflict; it isn't).**
An earlier pass of this README read the `isChat` block's surface (message list + composer)
and flagged it against this project's CLAUDE.md rule *"there is no chat feature — every
session runs the agent's own terminal UI."* Having now read the actual `blocks`/`terminal`
code, the prototype is a good structural match, not a conflict:

- The prototype's `toggleChatView`/`chat.isBlocks`/`chat.isRaw` split is **already the real
  app's `SessionViewCubit`** (`lib/feature/blocks/presentation/blocks_screen/logic/
  session_view_cubit.dart`), toggled today from `TerminalScreen`'s app bar
  (`context.read<SessionViewCubit>().toggle`, `Icons.terminal` ↔
  `Icons.view_agenda_outlined`). Build the toggle's new icon/color styling there — the
  behavior already exists.
- Every block "kind" in the mockup already has a real widget under
  `lib/feature/blocks/presentation/blocks_screen/ui/widgets/`: `block_card.dart` (command
  group/diff/thinking/plan/permission — cross-check each `sc-if item.is*` branch against
  this file's existing kind-switch), `block_find_bar.dart` (= the "Find in blocks" bar),
  `block_selection_bar.dart` (= the selection-mode bar — copy behavior is identical: it
  already copies selected blocks to the clipboard and shows a snackbar), `block_action_sheet.dart`
  (= the long-press sheet — see the one real difference below), `context_readout_chip.dart`
  (= the `chat.ctxPct` usage chip), `block_nav_controls.dart` (= jump-to-latest / find
  prev-next), `sticky_block_header.dart`, `turn_group_status.dart`, `block_todo_list.dart`
  (= the plan/step list), `block_question_options.dart`. Restyle these to the new tokens;
  do not create new widgets for anything already here.
  **Correction (2026-09-08): this line was wrong about `block_card.dart` specifically.**
  The widget existed, but its *structure* — a bordered card per block with a uniform
  header row (chevron + status dot + name + "you"/"agent"/"tool" kind-label chip) — did
  not match the mockup at all. The mockup has no per-block card or generic header; it's a
  rail-based timeline (a small colored dot + connecting line down the left margin, plain
  content to the right, bespoke per kind) with a chat bubble for user turns and a
  thin-divider row for notices. This has since been fixed — see `session_detail.md`'s
  "Block kinds" section for the corrected, as-built structure. The lesson: "a widget
  exists for this kind" and "that widget's visual structure matches" are different claims,
  and this doc conflated them.
- The raw view is `lib/feature/terminal/presentation/terminal_screen/ui/widgets/
  raw_terminal_pane.dart` + `terminal_key_row.dart` (the control-key row) — built on the
  vendored `xterm` package for the actual scrollback, not a plain `chat.rawLines` list.

**Three specific, real differences to design around (not blanket "don't port"):**

1. **Stopped-agent presentation differs.** The prototype shows an inline danger *banner*
   ("The agent controller is stopped" / "Resume agent" / "Shell") sitting above still-visible
   block content. The real app's `terminal_dead_overlay.dart` instead replaces the ENTIRE
   body with a full-screen `AppEmptyState` ("Session terminated" / "Restore session") once
   the terminal closes — you can't see prior blocks behind it. `session_detail.md` documents
   both; before implementing, someone should decide whether to keep the existing
   overlay-replaces-content behavior (simpler, already built, per this repo's actual state
   model) or adopt the banner-over-content behavior (matches the prototype more closely,
   but is new product behavior, not just a reskin) — flag that specific choice to the user,
   don't decide it silently.
2. **Command menu shape differs, action set is identical.** The prototype's `cmdDefs` are
   `stop`/`compact`/`model` opened from a "bolt" trigger as a bottom-sheet menu
   (`toggleCmdMenu`/`chat.cmdMenuOpen`). The real `SessionCommandRow` (`lib/feature/blocks/
   presentation/blocks_screen/ui/widgets/session_command_row.dart`) already implements the
   exact same three commands, but as an always-visible 3-button row above the composer —
   by explicit design ("pixel-identical in every session state," per its own code comment).
   Keep the existing always-visible row; restyle its container/colors/radius to the new
   tokens. Do not add a modal "bolt" sheet — it would duplicate existing, deliberately
   simpler UI.
3. **Long-press sheet's action set is narrower than the mockup's, correctly so.** The
   prototype's copy sheet offers "Copy message" plus, for user-turn bubbles, "Edit message"
   and "Reply." The real `block_action_sheet.dart` offers `copyBlock`/`copyCommand`/
   `copyOutput`/`rerun` — no edit/reply, because there is no user-editable chat turn to
   edit or reply to in a terminal session. This is correct as-is; restyle it, don't add
   edit/reply affordances back in.

The prototype's composer (text field + mic + send, `chat.hasDraft` swapping mic↔send) is
also already real: `terminal_composer.dart` already has a `MicKey` (dictation feature) and
a send button. Its send button currently uses `skin.blue` rather than `skin.accent` — a
restyle-token touch-up, not a rebuild, and one Phase 5 didn't already cover (verify against
`components.md`'s file list before assuming it's done).

### Screens NOT covered by this design pass

The prototype has no notifications list, usage, preview, or blocks screen, and no
dictation UI — the bell icon on the Agents tab appbar (`S.bellWrap`/`S.bellBadge`) has no
tap handler in the source (decorative badge only). `lib/feature/{notification,usage,
preview,blocks,dictation}` are unmodeled by this prototype; do not invent designs for them
here — carry over whatever look `components.md`'s shared tokens/widgets naturally produce
when those screens are eventually designed, but don't treat anything in this doc set as
their spec.

## Global screen conventions

- Page background is always `context.skin.bgBase`; cards/rows sit on `bgSurface` with a
  `borderDefault` 1px border and the radius scale in `components.md`.
- Every full-screen entrance and staggered list uses `AppMotion.staggerDelay(index)` +
  `AppMotion.slow` fade-up (`AppMotion.easeOut`); sheets slide up with `AppMotion.spring`;
  dialogs/popovers pop in with `AppMotion.spring`; scrims fade with `AppMotion.easeOut`.
- Screen-to-screen navigation itself has **no transition treatment** in the prototype
  (verified — it swaps screens instantly); don't invent a custom page-route transition
  for screens 1-8 unless the user asks — use whatever this app's `AppRouter` already does
  by default.
- A phone-frame status-bar inset in the mockup is not a design value — always use
  `SafeArea`/`MediaQuery` insets, never a literal padding lifted from the mockup.
- Bottom sheets/dialogs use `AppSheetChrome`/`AppDialog` (see `components.md`); never
  hand-roll scrim + rounded-top-container markup per screen.

## Suggested implementation order

1. Home shell (bottom nav, 4 tabs) if not already wired to the new tab set.
2. Sessions board (`tab0`) — most core widgets get exercised here (cards, chips, empty
   state, shimmer loading, status dots) so building it first validates Phase 5 widgets.
3. Onboarding + Connections (screens 1-2) — smallest, most self-contained.
4. Orchestrator, Pull Requests, Settings (tabs 1/2/3) — reuse Sessions-board patterns.
5. Spawn (screen 8).
6. Blocks/terminal session-detail (screen 7) — last, since it's the largest and reuses
   patterns from the sessions board; get the user's call on the stopped-agent
   banner-vs-overlay question (above) before restyling `terminal_dead_overlay.dart`.

Screens without their doc built yet render as whatever placeholder this app's router
already falls back to — don't block other screens on screen 7.

## How this was decoded (for re-derivation)

`Operator Mobile - standalone.html` is a self-contained "bundler" export: a
`<script type="__bundler/manifest">` JSON blob maps `uuid → {mime, compressed, data
(base64)}` for every embedded font/image (gzip when `compressed:true`), and a
`<script type="__bundler/template">` holds the actual page (HTML + inline `<style>` +
one big JS `Component extends DCLogic` class) as a JSON-escaped string. The real design
truth is the `Component` class's `const S = {...}` style-object literal and its `LIGHT`/
`DARK` token objects — NOT the many dead `.sk-*`/`tg-*`/`obs-*` CSS rules elsewhere in the
file, which are unrelated leftover boilerplate from a different base template and were
excluded throughout every phase.
