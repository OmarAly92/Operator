# Sessions board ("Agents" tab)

Screenshots: `01-loaded-dark.png`, `02-loading-dark.png`, `03-empty-dark.png`,
`04-loaded-light.png`, `05-loaded-filter-needs-dark.png` (all in this directory).

Shared docs: [`../README.md`](../README.md) · [`../colors.md`](../colors.md) ·
[`../typography.md`](../typography.md) · [`../motion.md`](../motion.md) ·
[`../components.md`](../components.md)

## Part A — Spec

### Purpose / context

The first tab (`tab0`) of the bottom-nav home shell (`lib/core/app_routes/home_shell.dart`)
and the default screen a paired user sees. Lists every active agent session, grouped by
what state it's in, with a filter row and a FAB to spawn a new one. Has three top-level
states — **loading**, **empty**, **loaded** — that are mutually exclusive (only one is ever
shown).

### Layout tree (top → bottom)

```
Scaffold (bg: skin.bgBase)
├─ Appbar (bgChrome background, borderSubtle bottom border, minHeight 56, padding 16 horiz)
│  ├─ "Agents" title — style19SemiBold (Display family, letterSpacing -0.3)
│  ├─ flex spacer
│  └─ Bell icon (36×36, centered) + badge (top:2,right:2, accent bg, onAccent text,
│     radius 9, padding 2px 5px, "2") — DECORATIVE, no tap handler in the prototype
├─ Body (flex:1, scrollable, bottom padding 40 to clear the FAB)
│  ├─ [state: loading] → see "Loading state" below
│  ├─ [state: empty]   → see "Empty state" below
│  └─ [state: loaded]  → see "Loaded state" below
└─ FAB (absolute, right:20 bottom:88, 56×56 circle, accent bg, onAccent "+" icon 24px,
   shadow `0 4px 12px rgba(0,0,0,0.25)`) — always visible except in the loading state
   (verify against PNGs: FAB is present in loading/empty/loaded, absent only mid-syncing
   per 02-loading-dark.png showing it present too — so actually always visible)
```

### Loading state (`02-loading-dark.png`)

Centered column, `position:absolute inset:0`, fade-in (`AppMotion.easeOut`, `AppMotion.base`
≈180ms): `AppExpressiveLoader` at 52px sized to `skin.accent`, 14px gap, then "Syncing
agents…" in `style12p5Medium` / `textTertiary`.

### Empty state (`03-empty-dark.png`)

Centered column, top padding 44/side 34, pop-in (`AppMotion.spring`, `AppMotion.slow`):
- Brand orb — `AppEmptyState`'s floating orb (88×88 circle, radial gradient
  `#6CDB97 → #15A552 → #0C5C2E`, glow shadow `0 12px 44px rgba(26,203,100,0.35)`,
  `AppMotion.orbFloat`/`orbFloatOffset`/`easeInOut`, bounded per `components.md`'s testing
  note), margin-bottom 22.
- "No agents running" — `style21Bold` (Display family), margin-bottom 8.
- "Spawn an agent to start work, or refresh if you expected one here." — `style13p5Regular`
  / `textSecondary`, line-height 1.45, margin-bottom 22.
- "Spawn agent" primary pill button — `style16SemiBold`/`onAccent` on `accent`, pill radius,
  minHeight 50, padding 0 26, glow shadow `0 6px 18px rgba(26,203,100,0.25)`, press via
  `AppMotion.pressScaleDefault` + `spring` → opens screen 8 (Spawn).
- "Refresh" quiet text button — `style13p5Medium`/`textSecondary`, minHeight 44 → re-triggers
  loading state.

### Loaded state (`01-loaded-dark.png`, `04-loaded-light.png`, `05-loaded-filter-needs-dark.png`)

**Filter row** (`radiusPill` chips, horizontal scroll, gap 8, padding `2px 16px 12px`):
five chips — All / Needs you / Working / Mergeable / Archive — each `label + count`badge.
Active chip: `tintGreen` bg, no border, text color `brandInk` (light: literal `#117E3F`
override per `components.md`'s judgment call, NOT `skin.accent` — flagged there as
low-contrast-on-tint in light mode; dark: `skin.accent`). Inactive: `bgSurface` bg,
`borderDefault` 1px border, `textSecondary` text. Text `style12p5SemiBold`, count in
`mono11Regular` (`brandInk` when active else `textTertiary`).

**Grouped sections**, rendered top-to-bottom in this FIXED order — Working, Needs you (label
"NEEDS YOU" but internal zone key `action`), In review (zone key `pending`), Ready to merge
(zone key `merge`) — **a zone section is omitted entirely when it has zero sessions** (verify:
`boardSections` filters `zoneBuckets[z].length` truthy before mapping). Section header:
label uppercased + count, `style11SemiBold` colored by zone (working=`orange`,
action=`amber`, pending=`textTertiary`, merge=`green`), padding `18px 16px 8px`.

**Session card** (`CARD_SURFACE`: `bgSurface` bg, `radiusCard`(14) radius, `borderDefault`
1px border, padding 13, margin `5px 16px`, press scale `pressScaleDefault`+`spring`,
staggered entrance `AppMotion.staggerDelay(index)` + fade-up):
- Top row (gap 9): avatar (20×20 — harness logo image with `radiusXs`(4) corners if the
  harness is a known key, else a circular `bgElevated` initial-letter badge, `harness[0]`
  uppercased, or `?` when `harness` is null) · title (`style15SemiBold`/`textPrimary`,
  flex, line-height 1.3) · status chip (pill, padding `4px 9px 4px 8px`, tinted bg matched
  to the status color — see status table below — falls back to `bgSubtle` for
  neutral-colored statuses, dot 7×7 + label `style11p5SemiBold` in the status color; the
  dot **breathes** (`StatusDot`, `breatheActive`=1.6s) only for `working`/`detecting`).
- Meta row (`paddingLeft:29` to align under the title, margin-top 7): `project · branch`
  in `mono11Regular`/`textTertiary`, ellipsized; an optional issue chip
  (`mono10Regular`/`blue` on `tintBlue`, radius 5, padding `2px 6px`) when the session has
  a linked issue; the relative timestamp (`mono11Regular`/`textTertiary`) right-aligned.
- Optional PR row (only when the card has a PR): top border `borderSubtle`, padding-top 9,
  `call_merge` icon (14px, `green`) + PR text (`mono11Regular`/`textSecondary`).
- Tapping anywhere on the card → opens screen 7 (session detail) for that session id.
  **Per README's screen-7 flag: this navigates into the TERMINAL feature
  (`session_route` → `TerminalScreen`), not a chat-bubble screen** — don't wire this
  tap to anything resembling the prototype's `isChat` mockup literally.

**Archive section** — shown whenever the active filter is "All" or "Archive" (i.e. hidden
under Needs you/Working/Mergeable filters): header "ARCHIVE" + count
(`style11SemiBold`/`textTertiary`), then each archived card at `opacity: 0.72` (same
`CARD_SURFACE`, `cardStyleMuted`), no PR/issue rows shown for these in the dummy data.

If a filter yields zero sections and the archive is also hidden, show "Nothing here right
now." (`style13p5Regular`/`textTertiary`, centered, padding `34px 16px`) — **not
independently verified against a live click** (no filter combination in the dummy data
actually empties both); implement per this text but flag if untestable with the dummy set.

### Status → color/label table (`statusVisual`, verbatim from source)

| `status` | Color | Label | Breathing dot? |
|---|---|---|---|
| `spawning` | `blue` | Starting | no |
| `working` | `orange` | Working | **yes** |
| `detecting` | `orange` | Detecting | **yes** |
| `needs_input` | `amber` | Needs input | no |
| `changes_requested` | `amber` | Changes req. | no |
| `stuck` | `red` | Stuck | no |
| `errored` | `red` | Crashed | no |
| `ci_failed` | `red` | CI failed | no |
| `pr_open` | `textSecondary` | PR open | no |
| `review_pending` | `textSecondary` | In review | no |
| `approved` | `green` | Approved | no |
| `mergeable` | `green` | Mergeable | no |
| `merged` | `green` | Merged | no |
| `done` | `green` | Done | no |
| `idle` | `textTertiary` | Idle | no |
| `exited` | `red` | Exited | no |
| `killed` / `terminated` | `textTertiary` | Terminated | no |
| anything else | `textTertiary` | the raw status string, or "unknown" | no |

### Grouping logic (verbatim port — `attentionOf` → `boardZoneOf`)

```
attentionOf(session):
  status in {merged, done, killed, terminated, cleanup, errored} → 'done'
  status in {mergeable, approved}                                → 'merge'
  status in {needs_input, stuck}                                 → 'respond'
  status in {ci_failed, changes_requested}                       → 'review'
  status in {pr_open, review_pending}                            → 'pending'
  else                                                            → 'working'

boardZoneOf(session):
  attentionOf == 'merge'              → zone 'merge'
  attentionOf == 'pending'            → zone 'pending'
  attentionOf in {'respond','review'} → zone 'action'
  else (including 'working' AND 'done'!) → zone 'working'
```

**⚠️ Verbatim quirk, do not silently "fix":** because `boardZoneOf`'s final `else` catches
both `'working'` and `'done'`, a session with status `merged` or `done` lands in the
**Working** section, not a "Done" section (there is no Done section in this design — verify
against `01-loaded-dark.png`: "Bump dependencies to latest" (`done`) and "Ship pricing page
redesign" (`merged`) both render under **WORKING**, alongside "Fix auth redirect loop"
(actually `working`)). This is the prototype's actual behavior, reproduced faithfully in
`01-loaded-dark.png`. If this is undesired, it's a product decision to raise with the user,
not a discrepancy to correct unilaterally while porting.

Archived sessions (`session.archived === true`) are excluded from all zone bucketing and
shown only in the Archive section.

### Filter chip counts (verbatim, from the 9-session dummy set — 7 live + 2 archived)

All=7, Needs you=2 (zone `action`), Working=3 (zone `working`, includes the 2 done/merged
quirk cards above), Mergeable=1 (zone `merge`), Archive=2. There is no explicit "In review"
filter chip even though there's an "In review" section (`pending` zone) — verify: the
filter row's 5th chip ("Archive") is horizontally clipped in `01-loaded-dark.png`; a 6th
"In review" filter does not exist in the `agentFilters` array — selecting nothing filters
directly to the pending zone; it's only reachable via "All".

### Dummy content (verbatim — `SESSIONS` array, 9 entries)

| id | title | harness | project | branch | issue | status | when | PR |
|---|---|---|---|---|---|---|---|---|
| s1 | Fix auth redirect loop | claude-code | operator | fix/auth-redirect | — | working | 2m | — |
| s2 | Add dark mode toggle settings | cursor | operator-web | feat/dark-mode | github:482 | needs_input | 14m | — |
| s3 | Investigate flaky CI on windows runner | devin | operator | fix/ci-windows | — | ci_failed | 38m | — |
| s4 | Refactor payment retry logic | codex | billing-service | refactor/payment-retry | — | mergeable | 1h | #142 "PR #142 open" |
| s5 | Update onboarding copy for v2 | copilot | operator-web | docs/onboarding-copy | — | pr_open | 3h | #138 "PR #138 open" |
| s6 | Bump dependencies to latest | goose | operator | chore/deps-bump | — | done | 5h | — |
| s9 | Ship pricing page redesign | cursor | operator-web | feat/pricing-redesign | — | merged | 1d | #120 "PR #120 merged" |
| s7 *(archived)* | Spike: websocket reconnect backoff | kimi | operator | — | — | terminated | 1d | — |
| s8 *(archived)* | Old prototype UI experiment | *(none)* | operator-web | — | — | killed | 2d | — |

Known harness logo keys (render an image avatar instead of an initial): `claude-code`,
`cursor`, `codex`, `copilot`, `devin`, `goose`, `kimi`. `s8` has no harness → shows a `?`
initial badge.

### Motion

- Cards: staggered fade-up entrance, `AppMotion.staggerDelay(index)` (120ms + 40ms×index)
  then `AppMotion.slow` (260ms) `easeOut`, index counted continuously across ALL sections
  (not reset per section) then continuing into the archive list.
- Loading spinner: `AppExpressiveLoader` (see `components.md`).
- Empty state: `saPop` container entrance + orb `orbFloat` loop (see `components.md`'s
  bounded-cycle testing note).
- Working/detecting status dots: `StatusDot` breathing, `breatheActive` period.
- Filter chip tap: instant recolor, no special transition documented in source.

### Flutter mapping

`lib/feature/sessions/presentation/sessions_screen/` (screen→feature map row 3 in
`README.md`). No sheets/dialogs owned by this screen — the "⋮" pattern from screen 2
(connections) does not appear here; long-press was not found in source (grep for
`onLongPress`/`contextmenu` equivalents — none).

## Part B — Implementation brief

**# TASK:** Build the Agents sessions-board screen (loading/empty/loaded states, filter
chips, grouped session cards, archive section) as UI-only — dummy data from Part A above,
no backend wiring, no real `SessionsCubit` data yet.

**Do this FIRST:** (a) read `docs/design/README.md` in full — screen→feature map, global
conventions, "already implemented" inventory; (b) invoke the `/flutter-knowledge` skill —
authority on this project's feature tree, cubit conventions, screen/body split, DI,
routing. Only then proceed below.

**Target feature — exact path:** `lib/feature/sessions/presentation/sessions_screen/`
(from `README.md` row 3). Read what's already there (`Glob`/`Read` the existing
`sessions_screen/ui/`, `sessions_screen/logic/`) before writing anything — this screen
likely already exists with real data wiring; this pass is a **visual restyle** of that
existing screen to match Part A, not a from-scratch build. Identify and preserve whatever
real `SessionsCubit` states/streams already exist; only the presentation (colors, spacing,
components) changes.

**Already exists — do NOT recreate:** `AppSkin`, `AppTextStyle`, `AppMotion`,
`AppConstants` radius scale, `CardSurface`-equivalent (`app_container.dart`'s
`pressScale: true` mode per `components.md`), `AppExpressiveLoader`, `AppEmptyState`
(bounded orb), `StatusDot`, `AppPill` (for filter chips — verify its active/inactive
variants match the light-mode `brandInk` override judgment call in `components.md` before
assuming a plain `skin.accent` swap works).

**Files to create/change:** restyle `sessions_screen/ui/sessions_screen.dart` (and its
body/widgets subfolder) to the layout tree above; add/restyle a session-card widget under
`sessions_screen/ui/widgets/` consuming `AppContainer`+`StatusDot`+`AppPill` primitives;
add a filter-chip-row widget if one doesn't exist, backed by `AppPill`.

**Key implementation points:**
1. Port `attentionOf`/`boardZoneOf` and the status table exactly, including the
   working/done quirk — do not "fix" it without flagging to the user first (see Part A).
2. Card tap navigates to the session-detail route (screen 7) — check `README.md`'s
   screen-7 flag before wiring anything chat-bubble-shaped there.
3. Bell icon badge is decorative only (no `notification` feature wiring here).
4. FAB opens Spawn (screen 8) — `lib/feature/spawn/presentation/spawn_screen/`.
5. Stagger index must be continuous across sections + archive, not reset per section.

**Dummy data:** the `SESSIONS` table in Part A above, verbatim.

**Localization:** this repo's CLAUDE.md convention — inline English strings, **no
LocaleKeys/easy_localization catalogue**. Do not add translation keys for this screen's
copy.

**Definition of done:** `flutter analyze` clean; all three states (loading/empty/loaded)
match their PNGs in both light and dark; filter chips correctly bucket the dummy sessions
per the counts table; existing `sessions_screen` tests updated for the new visuals (not
weakened) and passing; card tap and FAB tap navigate correctly.
