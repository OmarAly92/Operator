# Session detail (screen 7 — `isChat` in the prototype)

Screenshots (this dir): `00-source-agents-list-light.png` (entry point), `01-blocks-dark.png`,
`02-raw-view-dark.png`, `03-find-bar-dark.png`, `04-cmd-menu-dark.png` (shown with the find
bar still open above it — both were captured in one pass; treat the sheet content as the
subject), `05-longpress-sheet-dark.png`.

Shared docs: `../colors.md`, `../typography.md`, `../motion.md`, `../components.md`,
`../README.md` (**read README's "Screen 7 — corrected assessment" section before this
file** — it has the real code cross-references this doc leans on throughout).

## Purpose / context

Opened by tapping a session card on the Agents board (or an Orchestrator project card) —
`lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart` resolves
the session/orchestrator id and hands off to the real `TerminalScreen`. This is **not** a
new screen to build from scratch: it is a restyle of already-working functionality split
across two features:

- **`lib/feature/blocks/presentation/blocks_screen/`** — the structured "blocks" view
  (command groups, diffs, thinking, plan, permission, running-command), the find bar, the
  selection bar, the long-press action sheet, the context-usage chip.
- **`lib/feature/terminal/presentation/terminal_screen/`** — the header bar, the
  blocks/raw view toggle, the raw xterm pane + control-key row, the composer (text field +
  mic + send), the stopped-agent presentation.

## Layout tree — Blocks mode (`chat.isBlocks`, default)

```
Header bar (terminal feature: GlobalAppbar.sub + custom actions)
  ← back                title + connection dot        status pill   🔍   ⇄ view-toggle
                         subline (harness · project)
[Find bar — only when open, see "Owned UI" below]
[Stopped banner — only when chat.showStoppedBanner, see "Owned UI"]
Block scroll list (blocks feature: BlocksBody / block_list.dart)
  user turn (chat bubble, right-aligned) + timestamp
  rail item (thinking / group / diff / plan / permission / running), each with:
    left rail: colored node dot + connecting line down to the next item
    right: the item's kind-specific card (see "Block kinds" below)
  notice row (centered divider text, e.g. "CONTEXT COMPACTED · 128k → 34k")
[Context-usage chip — bottom-right overlay, only once scrolled down]
[Jump-to-latest FAB — bottom-right overlay, only when not already at bottom]
Composer (terminal feature: TerminalComposer)
  text field (multiline, min 40 / max 108px height) | mic key | send button
```

## Layout tree — Raw mode (`chat.isRaw`)

```
Header bar (same as above, view-toggle icon flips to indicate "switch to blocks")
Raw scrollback (terminal feature: RawTerminalPane, built on the vendored xterm package —
  NOT a plain text list like the prototype's `chat.rawLines` array)
Control-key row (terminal_key_row.dart): esc / tab / ^C / ← / ↑ / ↓ / → / ↵
Composer (same TerminalComposer as blocks mode)
```

## Header bar spec

- Back chevron (`arrow_back_ios_new`, `I.back`) → `goHome`. Real: `Navigator.pop`.
- Title = session title (`chat.title`), truncated at 22 chars + "…" in the real
  `TerminalScreen` (`args.title.length > 22`) — the prototype doesn't show this truncation
  in its single dummy title; keep the real truncation, it's correct defensive behavior.
- Connection dot next to the title (`chat.connDotStyle`) — small circle, green when
  connected.
- Subline: harness · project, e.g. `claude-code · operator` (`mono` style, `textTertiary`).
- Status pill (`chat.pillStyle`/`pillDotStyle`/`pillLabelStyle`) — dot + label, e.g. amber
  dot + "1m24s" in the screenshots (a live elapsed-time readout while working). Reuse the
  `attentionOf`/`statusVisual`-style color mapping already established for session cards
  (see `sessions_board.md` for the exact status→color table) — same status vocabulary,
  same colors.
- 🔍 search icon (`I.searchSm`) — only shown when `chat.isBlocks` — opens the find bar.
  Real: already a header action (`data-dc-tpl="317"` in the prototype's DOM); pair with
  `block_find_bar.dart`.
- View-toggle icon (`chat.viewIcon`) — flips between a "terminal" glyph (showing blocks,
  offering to switch to raw) and a "blocks" glyph (showing raw, offering to switch to
  blocks). **Already wired**: `TerminalScreen`'s app bar action calls
  `context.read<SessionViewCubit>().toggle`, icon `Icons.terminal` ↔
  `Icons.view_agenda_outlined`, color `skin.blue` (retint to `skin.accent` per the reskin).

## Block kinds — corrected 2026-09-08 (was wrongly marked "restyle only")

**This section originally said every block kind already had the right visual
structure in `block_card.dart` and only needed a token restyle. That was wrong.** A
real screenshot comparison showed the app was rendering every block as a bordered
card with a uniform header row (chevron + status dot + name + a "you"/"agent"/"tool"
kind-label chip) — the mockup has no such generic card or header. `block_card.dart`
has since been rewritten to the rail-based structure below; this section now
documents what's actually built, not what was assumed.

`block_card.dart` now dispatches each `SessionBlock` to a `RailKind` (`railKindOf`)
rather than rendering one generic card shape:

- `BlockKind.prompt` → a right-aligned chat bubble (`_UserBubble`), no rail column.
- `BlockKind.notice` / `BlockKind.compaction` (and anything whose `detail` is not a
  `QuestionBlockDetail`) → a thin divider-flanked label row (`_NoticeRow`), no rail.
- `BlockKind.reasoning` → `_ThinkBody`: title + chevron header, a collapsed-state
  one-line preview, and — when expanded — a left-bordered "blockquote" body (no card).
- `BlockKind.tool` (no file-change detail, no MCP signal) → `_GroupBody`: title + meta
  + chevron header, and — when expanded — a bordered `_CmdCard` listing
  command/output. The **only** bordered container left anywhere in the block list.
- `BlockKind.tool` whose `toolName` looks like an MCP tool (or carries a
  `McpToolBlockDetail`) → the same `_GroupBody`, purple rail node, "mcp" meta.
- A block whose `detail` is `FileChangeBlockDetail` (tool or assistant) → `_DiffBody`:
  header with +/- totals, always-expanded `_CmdCard` of per-file stats.
- `BlockKind.todo` → `_PlanBody`: "Plan · N of M done" header + `BlockTodoList`'s
  status-icon step rows (done/active/pending), no card.
- `BlockKind.permission` → `_PermissionBody`: the one remaining tinted (not bordered)
  card, `skin.tintAmber`, with a mono command chip and **three** buttons — Deny, Allow
  once (primary), Always. **Always is visual-only and does not call `decide`** — the
  daemon's decision contract (`backend/internal/session_manager/decision.go`) only
  accepts `"allow"`/`"deny"`, so there is no behavior string for a third option to send.
- A `detail is QuestionBlockDetail` block (assembled onto `BlockKind.notice` by
  `question_asked` events) → `_QuestionBody`: not modeled by the prototype at all, so
  it keeps a plain title + `BlockQuestionOptions`, amber rail node ("needs input").
- A running tool block (`BlockStatus.running`) gets a trailing `_RunningRow` appended
  below its group body: typing dots + orange command text + a "Stop" action wired to
  `SessionCommandCubit.run('stop')`. The rail node itself keeps the existing
  status→color vocabulary (`blockStatusColor`, `running` = `skin.blue`) rather than
  switching to the mockup's orange node — only this trailing row's own text uses
  orange, per an explicit instruction not to touch `block_status_dot.dart`'s
  established status-color mapping.

Each rail item has: a colored node dot (`nodeStyle`) on a vertical connecting line
(`hasLine`), and a kind-specific body to its right.

**Deviations from the literal mockup copy, and why:** the reasoning header keeps the
real event title ("Reasoning") instead of a fabricated "Thought for Ns" — no per-block
duration exists in the current event data. A tool/MCP group's meta segment ("N cmds ·
Ns", "mcp · 0.4s") is only shown when derivable (running/error state) and omitted
otherwise, rather than inventing counts the assembled `SessionBlock` doesn't carry —
`ShellBlockDetail`/`FileChangeBlockDetail`/`McpToolBlockDetail`/`PlanBlockDetail` are
real wire types but are not currently populated by `block_assembly.dart`'s
`assembleBlocks`, so the corresponding rail treatments only activate when a future
backend change (or a test fixture) actually supplies that detail; the common path
today (`UnknownBlockDetail`) renders through the group/text fallback.

**Sticky header:** only kinds with a natural header row keep one —
`RailKind.think`/`group`/`mcpGroup`/`diff`/`plan` (`railKindHasHeader` in
`block_card.dart`). `sticky_block_header.dart` renders nothing for a plain-text,
permission, question, notice, or user-bubble block at the top of the viewport, since
none of those have a header-shaped summary to pin.

**Interaction consolidation, flagged deliberately:** the old card had two distinct
long-press regions per block — the header (enters selection mode) and the body (opens
the copy/action sheet) — for every kind, including a user prompt (header = "Prompt"
label, body = the prompt text). The rail redesign keeps both regions, but only for the
two kinds that still have a real header/body split (reasoning, command/tool group):
header long-press still enters selection, body long-press still opens the action
sheet. For every headerless kind (plain text, diff, plan, permission, question,
notice), the whole content is now the "body" region for the action sheet, and — for
the user bubble specifically — the small timestamp label below the bubble is the
"header" region for entering selection mode (bubble long-press → action sheet,
timestamp long-press → select). This was a deliberate, minimal-risk consolidation
made necessary by removing the generic per-block header, not an accidental behavior
change; all of it is covered by `test/feature/blocks/presentation/block_selection_test.dart`.

1. **Thinking** (`isThink`) — collapsible. Header: "Thought for 12s" + chevron. Body when
   open: paragraph of reasoning text, `textFaint`-ish tone (`skin.textFaint` node dot).
   Verbatim dummy body: *"A redirect loop on expiry usually means the refresh path and the
   401 interceptor are the same code path. Worth checking whether refresh failures are
   re-entering the interceptor instead of bubbling up, and whether concurrent requests each
   trigger their own refresh."*
2. **Command group** (`isGroup`) — header: bold title + meta (e.g. "4 cmds · 6s") + chevron;
   body when open is a `cmdCard` (`skin.bgElevated`-ish surface) listing each command line
   in mono. Verbatim example — title "Explored the auth module", meta "4 cmds · 6s", lines:
   `rg -n 'refreshToken' src/auth`, `cat src/auth/refresh.ts`, `cat src/auth/guard.ts`,
   `git log -3 --oneline src/auth`. A second group example (title "Type check failed", meta
   "exit 2 · 3s", red node) has a `tone:'error'` line rendered in `skin.red` mono:
   `pnpm tsc --noEmit` then `src/auth/refresh.ts:52:11 — error TS2532:\nObject is possibly
   'undefined'.` — an MCP-flavored group also exists (title "linear · get_issue", meta
   "mcp · 0.4s", purple node) with a `tone:'muted'` second line — port the per-line tone
   variants (`default`/`error`/`muted`), not just a single mono style.
3. **Plain text** (`isText`) — a rail item with no card, just a paragraph directly on the
   rail (green node). Verbatim: *"Found it — refreshToken() re-enters the same 401 handler
   that called it, so an expired session bounces forever. Two concurrent requests also each
   kick off their own refresh, which invalidates the first token."*
4. **Diff** (`isDiff`) — header: title + green `+N` + red `−N` totals (no chevron, always
   "open"); body: one row per file, filename (mono) left, per-file `+N −N` stat right.
   Verbatim: title "Patched 2 files", `+34`/`−9`, files `src/auth/refresh.ts` (`+28 −7`),
   `src/auth/guard.ts` (`+6 −2`).
5. **Plan** (`isPlan`) — header: "Plan" + "N of M done"; body: a vertical step list, each
   step an icon (done=green check, active=amber filled ring, pending=empty ring) + label
   text (`textDecoration: line-through` + 0.65 opacity when done). Verbatim 4 steps: "Add a
   retry guard so a failed refresh bubbles up" (done), "Wrap refresh in a single-flight
   lock" (done), "Add a regression test for concurrent 401s" (active), "Update the
   session-expiry docs" (pending).
6. **Permission** (`isPermission`) — a standalone card (`skin.tintAmber` background,
   `radius 10`, no rail chevron/open-state): title in `skin.amber` SemiBold ("Agent wants to
   run a command"), the command in mono on a `bgSurface` chip below (color `#4DDB8A` dark /
   `#117E3F` light — a hardcoded green distinct from the semantic `green` token, keep it
   exact), then a 3-button row: **Deny** / **Allow once** / **Always**. Verbatim command:
   `pnpm test auth --runInBand`.
7. **Running** (`isRunning`) — a rail item shown only while `busy`: typing dots
   (`TypingDots`, per `components.md`) + the running command in mono (`skin.orange`,
   single-line ellipsis) + a "Stop" text action. Verbatim: `pnpm test auth`.
8. **User turn** (`isUser`) — right-aligned bubble (`item.bubbleStyle`, rounded
   `18px 18px 4px 18px` per the prototype's `userTurnWrap` transition spec) + a timestamp
   below it (`10:42`, `10:51`, or `now` for freshly sent messages). Long-press
   (`pressStart`/`pressEnd`) opens the action sheet — see below.
9. **Notice** (`isNotice`) — a centered divider row: a hairline, small caps label, hairline.
   Verbatim: `CONTEXT COMPACTED · 128k → 34k`.
10. **Sent-to-terminal echo** — when the user's message targeted the terminal instead of the
    agent (`SendTarget.terminal` in the real composer), it renders as a command-group-style
    rail item titled "Sent to terminal" / meta "keystrokes" instead of a chat bubble — this
    is the one place the prototype's own logic (not just this doc) already distinguishes
    "chat with the agent" from "raw terminal input," which lines up with the real
    composer's `SendTarget.agent`/`SendTarget.terminal` toggle (`terminal_composer.dart`).

Full conversation order in the dummy data (for a build-order sanity check / screenshot
matching): user turn → thinking → command group ("Explored…") → text → plan → diff →
command group ("Type check failed", error tone) → text → notice (context compacted) → user
turn (2nd message) → command group (MCP linear lookup) → permission card → (if busy) running
row.

## Composer spec

- **Blocks-mode / default**: rounded field (`radius 11`, `bgElevated`, `borderDefault`),
  placeholder text swaps between "Message the agent…" and "Send to terminal…" depending on
  `SendTarget` — already real (`terminal_composer.dart`). `MicKey` (dictation feature,
  already wired) sits left of the send button. Send button: 40×40, `radius 12`, currently
  `skin.blue` background — **retint to `skin.accent`**, `skin.onAccent` icon, per the
  reskin (this file was not in Phase 5's restyle list — verify against `components.md`
  before assuming done).
- **Raw mode**: same composer, plus a control-key row above it
  (`terminal_key_row.dart`): `esc` `tab` `^C` `←` `↑` `↓` `→` `↵`, each a small
  `bgElevated`/`borderDefault` chip.
- The prototype's "bolt" trigger next to the composer (`chat.cmdTriggerStyle`) does **not**
  need porting — see README's corrected assessment: the real `SessionCommandRow` already
  shows Stop/Compact/Model as an always-visible row, which the screenshots' cmd-menu sheet
  content (`04-cmd-menu-dark.png`) confirms is the identical action set, just presented
  differently.

## Sheets & dialogs owned by this screen

### Find bar (`block_find_bar.dart` — already exists)
Trigger: header 🔍 icon, blocks mode only. Screenshot: `03-find-bar-dark.png`. Layout: a
full-width bar replacing/overlaying the top of the scroll area — text input ("Find in
blocks"), a match counter ("0/0"), prev/next arrow buttons, a filter-toggle icon, and a
close (×) icon. `chat.showHidden`/`hiddenLabel` conditionally shows a "N hidden" label when
the filter excludes some matches. Dismissal: × icon, or presumably re-tapping the search
icon. Already real — restyle only (`block_find_bar.dart`, `block_nav_controls.dart` for
prev/next).

### Session-actions sheet (bolt menu equivalent → real always-visible row, not a sheet)
See composer note above — **do not build this as a bottom sheet**; it's the existing
`SessionCommandRow`. Documented here only because the prototype models it as an
overlay — screenshot `04-cmd-menu-dark.png` shows its content (Stop/red-tinted when
enabled+dangerous, Compact, Model — each with an optional trailing phase indicator:
spinner while sending, check when sent/confirmed, error icon when unconfirmed).

### Model picker (`model_picker_sheet.dart` — already exists)
Trigger: tapping "Model" in `SessionCommandRow`. Lists per-harness model names (e.g.
claude-code: sonnet/opus/haiku) as a plain `ListTile` list; tapping one calls
`cubit.run('model', model: model)`. Not visually specced by the prototype (no equivalent
screen state reached) — restyle its `ListTile`s to `AppText`/skin tokens if not already
done; keep the list logic as-is.

### Long-press action sheet (`block_action_sheet.dart` — already exists, narrower action set by design)
Trigger: press-and-hold (~700ms) on a block/bubble. Screenshot: `05-longpress-sheet-dark.png`.
**Prototype shows 4 rows for a user bubble**: a preview of the message text, "Copy message",
"Edit message", "Reply", "Cancel". **Real sheet shows exactly 4 action rows with no message
preview**: "Copy block" / "Copy command" / "Copy output" / "Re-run this prompt" (the
relevant subset depends on `BlockActionKind` for the tapped block — a user turn likely only
offers copy + rerun). Do not add "Edit message"/"Reply" — there is no editable user turn to
edit or reply to in this architecture (see README's point 3). Sheet chrome: `bgSurface`,
top corners `radius 22`, `SafeArea`-wrapped list, `borderSubtle` top hairline between rows,
row text `style13SemiBold`, trailing chevron `textFaint`. Tapping a copy action copies to
clipboard, shows a snackbar ("Copied") via `AppToast`/`context.showSnackBar`, and closes the
sheet — no separate "Copied to clipboard" toast overlay needs building (the real code
already does this inline; the prototype's separate `copiedToast`/`S.toast` state is the same
idea, just implemented as a snackbar instead of a custom toast — keep the existing snackbar
approach, or swap to `AppToast` per `components.md` if that's now the house style for
toasts elsewhere — check `components.md` for that call).

### Selection-mode bar (`block_selection_bar.dart` — already exists, exact match)
Trigger: (mechanism not confirmed from source alone — likely a multi-select entry point on
long-press-then-select, or a "select" action; check `blocks_cubit.dart`/`block_find.dart`
for the real trigger before writing code). Bar: bottom-docked, `bgSurface` background,
`borderSubtle` top hairline, "N selected" label (SemiBold), "Cancel" text button
(`textSecondary`), "Copy" text button (`skin.blue` when enabled — **retint to
`skin.accent`**, `textFaint` when no selection). Already copies concatenated block text via
`BlockActions.blocksToText` — restyle only.

### Stopped-agent presentation — flagged decision, do not resolve silently
Prototype (`chat.showStoppedBanner`): an inline red-tinted banner ABOVE the still-visible
block list — icon, "The agent controller is stopped." text, "Resume agent" primary action,
"Shell" secondary action. Real (`terminal_dead_overlay.dart`): a full-screen
`AppEmptyState` REPLACING the block list — "Session terminated" / "Restore session" (or,
for a shell-only session, "Shell closed" with no action). **Get the user's call before
touching this file**: keep the existing overlay-replaces-content behavior (less work,
matches current state model) or adopt the prototype's banner-over-content behavior (lets
the user re-read prior blocks while stopped — arguably better UX, but a real behavior
change, not a reskin). This screen's implementation should NOT proceed on this piece until
that's decided.

### Context-usage chip (`context_readout_chip.dart` — already exists)
Small floating chip, bottom-right of the scroll area, shown only once scrolled down
(`hasReadout: isBlocks && !this.state.atTop`) — a thin progress track (`ctxTrack`) filled to
`ctxPct` (verbatim dummy: `42%`) in `skin.blue` (**retint to `skin.accent`**), percentage
label beside it. Restyle only.

### Jump-to-latest FAB (`block_nav_controls.dart` — already exists)
Bottom-right circular button, `arrow_downward` icon, shown when not already scrolled to the
bottom (`chat.showLatest`). Restyle only.

## Motion

- Block entrance: staggered fade-up per new item as it streams in — `AppMotion.staggerDelay`
  + `AppMotion.slow`/`easeOut` (reuse the sessions-board stagger pattern, not a new one).
- Running-command row: `TypingDots` (`AppMotion.dotBounce`/`dotBounceStagger`/`easeInOut`)
  + the command's spin-in via `AppMotion.spin` if a small activity indicator accompanies it.
- Sheets (find bar open/close, action sheet, model picker): `AppMotion.spring`/`slow` slide
  up, scrim fade `AppMotion.easeOut`/`base` — per `AppSheetChrome` in `components.md`.
- Copy/rerun confirmation: whatever `AppToast`/snackbar transition `components.md`
  specifies — don't invent a new one here.

## Verified behaviors

- Tapping a session card on the Agents board navigates here (confirmed via screenshot
  walk: Agents tab → tap "Fix auth redirect loop" → session detail opens on the blocks
  view by default).
- View-toggle switches blocks ⇄ raw instantly, no transition (consistent with README's
  global "no screen-transition treatment" note — this is an in-screen state swap, not a
  route change, so it's outside that note's scope anyway, but still instant in the source).
- Long-press on a user bubble (~700ms hold) opens the copy/edit/reply sheet in the
  prototype; the real app's equivalent trigger and exact hold duration should be verified
  against `block_card.dart`'s actual gesture detector before assuming 700ms — the prototype
  source doesn't specify an exact threshold either (`pressStart`/`pressEnd` are plain
  mouse/touch down/up handlers with no explicit timer visible in the excerpts read).
- Command-menu / find-bar can be open simultaneously in the prototype's state model (seen
  in `04-cmd-menu-dark.png`, captured with both open) — likely not intentional multi-open
  UX, just independent boolean flags; the real always-visible `SessionCommandRow` sidesteps
  this ambiguity entirely since it's never a modal.

## Flutter mapping

| Piece | Feature | File(s) |
|---|---|---|
| Header bar, view-toggle, composer, raw pane, control-key row, stopped presentation | `terminal` | `terminal_screen.dart`, `terminal_composer.dart`, `raw_terminal_pane.dart`, `terminal_key_row.dart`, `terminal_dead_overlay.dart`, `terminal_status_bar.dart` |
| Block list, all block kinds, find bar, selection bar, action sheet, model picker, context chip, nav controls | `blocks` | `blocks_body.dart`, `block_card.dart`, `block_find_bar.dart`, `block_selection_bar.dart`, `block_action_sheet.dart`, `model_picker_sheet.dart`, `context_readout_chip.dart`, `block_nav_controls.dart`, `block_todo_list.dart`, `sticky_block_header.dart`, `turn_group_status.dart`, `session_command_row.dart` |
| Routing/resolution | `sessions` | `session_route/ui/session_route_screen.dart` |

## Implementation brief (Part B)

**TASK**: Restyle the existing session-detail UI (blocks + terminal features) to the new
design tokens. This is **retint/respace, not rebuild** — nearly every piece already exists
and works; see the per-widget notes above for exactly what stays as-is vs. gets a token
swap vs. needs a real decision from the user (the stopped-banner question).

**Do this FIRST**: read `docs/design/README.md` in full (especially the corrected Screen 7
section) and invoke `/flutter-knowledge` before touching any file. Then re-read this file's
"Block kinds," "Sheets & dialogs," and "Flutter mapping" sections alongside the actual
files in `lib/feature/blocks/` and `lib/feature/terminal/` side by side.

**Target feature paths (non-negotiable, split across two features — see mapping table
above)**: `lib/feature/blocks/presentation/blocks_screen/` and
`lib/feature/terminal/presentation/terminal_screen/`. Do not move blocks-owned widgets into
terminal or vice versa even though they render on the same screen.

**Already exists — do NOT recreate**: every widget listed in "Sheets & dialogs" and the
mapping table. The only genuinely new work here is retinting (`skin.blue` → `skin.accent`
in at least: `TerminalScreen`'s view-toggle icon, `TerminalComposer`'s send button,
`BlockSelectionBar`'s Copy button, `context_readout_chip.dart`'s fill/label,
`TerminalDeadOverlay`'s progress indicator) plus applying the new radius/spacing/text-style
tokens from `components.md` throughout.

**Key implementation points**:
1. Resolve the stopped-banner question with the user before touching
   `terminal_dead_overlay.dart` — see that section above.
2. Verify `block_action_sheet.dart`'s exact `BlockActionKind` set per tapped-block type
   before assuming every block offers all four actions.
3. Confirm the long-press hold duration and exact trigger widget in `block_card.dart`
   rather than assuming ~700ms from the prototype (which doesn't specify one either).
4. Keep `SessionCommandRow`'s always-visible 3-button layout — do not add a modal.

**Dummy data**: none needed — this screen already runs against real session data; a
before/after visual diff (screenshot the real app pre- and post-restyle) is the right way
to verify, not new dummy fixtures.

**Localization**: inline English per this repo's CLAUDE.md — no `LocaleKeys`.

**Definition of done**: `flutter analyze` clean; blocks view, raw view, find bar,
selection bar, long-press sheet, model picker, and the composer all visually match the new
tokens in both themes; the stopped-agent decision has been made explicitly (not defaulted);
no new widgets were created for anything in the "already exists" list above.
