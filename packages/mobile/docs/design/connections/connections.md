# Connections — "Your desktops"

Screenshots: `connections-dark.png` (default), `connections-light.png`,
`connections-menu-dark.png` (row "⋮" menu open), `connections-add-sheet-dark.png` (add
sheet), `connections-edit-sheet-dark.png` (edit sheet, pre-filled),
`connections-remove-dialog-dark.png` (remove confirm dialog).

Shared docs: [`../README.md`](../README.md) (screen→feature map, global conventions) ·
[`../colors.md`](../colors.md) · [`../typography.md`](../typography.md) ·
[`../motion.md`](../motion.md) · [`../components.md`](../components.md).

## Part A — Spec

### Purpose / context

The saved-desktops list (`state.screen === 'connections'`), shown instead of onboarding
once at least one desktop has been paired before, or reached via Settings → "Saved
connections". Lets the user reconnect to a known desktop, add a new one manually, start
a fresh QR pairing, or edit/remove an existing entry.

### Layout tree (top → bottom)

1. **Header row** (`S.onbHeaderRow`, shared with onboarding) — mascot 28×28 + "Operator"
   wordmark (`style15SemiBold`, `textPrimary`) + spacer + **add button**
   (`S.connAddBtn`): 32×32 circle, `bgElevated` background, centered "add" icon
   (`connAddIcon`, size 19, `textSecondary`) — opens the add sheet directly (same sheet
   as "Add manually" below).
2. **Scroll body** (`S.onbScroll`, `padding: 24px 20px 20px`):
   - Heading **"Your desktops"** — 24px Display-family Bold (same display-family gap as
     onboarding's heading — see that screen's Part B point 1), bottom margin 8, letter
     spacing -0.4, `textPrimary`.
   - Subtitle **"Tap a desktop to connect. Saved pairings stay on this phone."** —
     `style14Regular`, `textSecondary`, line-height 1.4, bottom margin 18.
   - **Connection group card** (`S.connGroup`): `bgSurface`, `radiusCard` (14),
     `border: 1px solid borderDefault`, `overflow: hidden` — a single card containing
     all rows with 1px `borderSubtle` dividers between them (not after the last row).
     - **Each row** (`rowStyle`): flex row, gap 11, `min-height: 62`,
       `padding: 10px 12px 10px 14px`, background `transparent` (or `bgElevated` while
       that row is connecting — see States below).
       - Icon wrap: 36×36, `radiusLg` (10), background `bgElevated` (or `tintGreen`
         while connecting), centered icon — "computer" (idle) or a spinning
         "progress_activity" (connecting, `linear infinite` 1s spin, `AppMotion.spin`) —
         **NOTE:** the busy state's icon color is a value called `brandInk` in the
         prototype (not a named `AppSkin` token) — cross-check `components.md`'s chip
         active-text judgment call (`#117E3F` light / `accent` dark) since it's the same
         concept (brand-colored ink on a tint background); reuse that resolution here
         rather than introducing a third variant.
       - Text column (flex: 1): name `style14p5SemiBold` `textPrimary`; meta line
         `mono11Regular` `textTertiary` (monospace — it's an IP address), top margin 3.
         Meta text is `"{address} · last connected {when}"` normally, or just
         `"Connecting…"` while busy, or `"{address} · not connected yet"` for a
         never-connected entry.
       - Trailing "⋮" button (`connMoreBtn`): 30×30, `radiusMd` (8), centered
         "more_vert" icon (18, `textFaint`) — opens the row's menu (see below).
   - **Primary button** "Pair a new desktop" — same spec as onboarding's "Pair Desktop"
     but 16px text (`connPairBtn` uses `style16Medium`, not 17) and top margin 20 instead
     of bottom margin 28. Starts a fresh QR pairing flow.
   - **"Add manually" link** (`connManualBtn`) — centered row, `style14SemiBold`
     `textSecondary`, "edit" icon (16, `textTertiary`) + text, height 44, top margin 4.
     Opens the same add/edit sheet as the header's add button, in **add** mode.

### States

- **Idle row**: as above.
- **Connecting row** (`connectingId === row.id`): icon wrap gets `tintGreen` background,
  icon becomes a spinning "progress_activity" glyph, row background becomes
  `bgElevated`, meta text becomes "Connecting…". Auto-resolves after 900ms in the
  prototype (`connectTo` sets a timeout that navigates to the home shell) — that's a
  prototype stub for "pairing succeeded"; the real app should drive this from actual
  connection state, not a fixed timer.

### Dummy content (verbatim)

- Heading: **Your desktops**
- Subtitle: **"Tap a desktop to connect. Saved pairings stay on this phone."**
- Row 1: **"Alex's MacBook Pro"** / **100.94.12.3** / last connected **2h ago**
- Row 2: **"Office iMac"** / **192.168.1.42** / last connected **3d ago**
- Buttons: **"Pair a new desktop"**, **"Add manually"**

### Motion

Same as global conventions (README.md) — sheets slide up with `AppMotion.spring`
(`slow`/260ms), scrims fade with `AppMotion.easeOut` (`base`/180ms), dialog pops with
`AppMotion.spring`. No screen-entrance animation (verified, see motion.md).

### Verified behavior

- Tapping a row (not the "⋮") calls `connect()` → connecting state → after a delay,
  navigates to the home shell (Agents tab). Real app: drive from actual pairing/connect
  result, not a timer.
- Tapping "⋮" opens **this row's** menu sheet (see below) — `stopPropagation`s so it
  doesn't also trigger the row's own connect tap.
- The header's "+" button and the "Add manually" link open the identical sheet in **add**
  mode (empty fields, placeholders "Studio iMac" / "192.168.1.42", title "Add a desktop",
  save button "Add desktop").
- "Pair a new desktop" navigates to onboarding's screen state in the prototype
  (`goPairing`) — i.e. the QR/pairing flow, same destination as onboarding's "Pair
  Desktop" button.

## Sheets & dialogs owned by this screen

### Row menu sheet

Screenshot: `connections-menu-dark.png`.

Trigger: tapping a row's "⋮" button.

Layout: `AppSheetChrome` (bottom sheet, `radiusCard`-topped, handle bar, see
components.md) containing:
- Title = the connection's name (`style17Bold`, `textPrimary`, e.g. "Alex's MacBook Pro").
- **Connect** row (`menuRow`, height 52, gap 12): "link" icon (19, `textSecondary`) +
  label `style15Medium` `textPrimary`.
- Divider (full-width, `borderSubtle`).
- **Edit details** row: "edit" icon (19, `textSecondary`) + label — opens the add/edit
  sheet in **edit** mode, pre-filled (see below).
- Divider.
- **Remove desktop** row: "delete_outline" icon (19, **`red`**) + label (`style15Medium`,
  **`red`**) — opens the remove-confirm dialog.

Dismissal: tap the scrim (`closeOverlays`), or any row action closes it as a side effect.

### Add / edit sheet

Screenshots: `connections-add-sheet-dark.png` (add mode), `connections-edit-sheet-dark.png`
(edit mode).

Trigger: header "+" button, "Add manually" link (→ add mode), or menu's "Edit details"
(→ edit mode).

Layout: `AppSheetChrome` containing:
- Title: **"Add a desktop"** (add mode) or **"Edit desktop"** (edit mode) — `style17Bold`.
- Field label **"Name"** (`style11SemiBold`, `textTertiary`, letter-spacing 0.6, bottom
  margin 6) + text input (height 44, `radiusLg`, `borderDefault` border, `bgElevated`
  fill, monospace `mono13p5Regular`, placeholder **"Studio iMac"**).
- Field label **"Address"** + text input, placeholder **"192.168.1.42"**.
- Button row: **Cancel** (ghost — `borderDefault` outline, `textSecondary` text,
  `style15SemiBold`, height 46, `radiusButton`, flex:1) + primary save button (flex:1,
  height 46, `radiusButton`, `accent` bg, `onAccent` text, `style15SemiBold`) labeled
  **"Add desktop"** (add mode) or **"Save changes"** (edit mode).

**⚠️ Quirk found while screenshotting, not a design choice — fix in implementation.**
In the prototype, opening "Edit details" correctly sets `formName`/`formAddr` state from
the selected connection (`openEditSheet` reads `c.name`/`c.address` into state — verified
in source), but the rendered `<input value="{{ formName }}">` visually shows the
**placeholder**, not the actual pre-filled value, in the captured screenshot. This reads
as a binding gap in the mockup's runtime, not intended behavior — **the real Flutter
implementation must pre-fill the Name/Address fields with the existing connection's
values when editing**, matching the prototype's evident intent (and matching what a user
would expect from "Edit details"), not what the screenshot literally shows.

Dismissal: Cancel closes without saving; primary button saves and closes
(`saveConn` — in add mode appends a new connection with `when: 'never'`; in edit mode
mutates the existing entry's name/address in place).

### Remove-confirm dialog

Screenshot: `connections-remove-dialog-dark.png`.

Trigger: menu's "Remove desktop" row.

Layout: `AppDialog` (see components.md) — scrim + centered card, `bgSurface`,
`radiusCard`, padding 20, "Dialog" shadow recipe (colors.md):
- Title **"Remove {name}?"** (e.g. "Remove Alex's MacBook Pro?") — `style16p5Bold`,
  bottom margin 8.
- Body **"This only removes the pairing from this phone. You can pair the desktop again
  anytime."** — `style13p5Regular`, `textSecondary`, line-height 1.45, bottom margin 16.
- Button row: **Cancel** (ghost, flex:1) + **Remove** (flex:1, `red` background, white
  text, `style15SemiBold`) — note this is the one button in the whole design system that
  uses literal white text rather than `onAccent`/a skin getter (it's a danger action on a
  `red` fill, not `accent`) — see `dangerBtn` in `components.md`'s `AppDialog` spec if not
  already covered; if `AppDialog` doesn't yet support a "danger" trailing-button variant,
  add one rather than hand-rolling this dialog outside `AppDialog`.

Dismissal: Cancel closes without changes; Remove deletes the connection and closes.

## Part B — Implementation brief

**# TASK:** Build the connections (saved-desktops) screen and its 3 owned sheets/dialogs.
UI-only — dummy data (the 2 sample connections above), no backend wiring yet.

**Do this FIRST, before any Dart:**
1. Read `docs/design/README.md` in full (screen→feature map, global conventions,
   "already implemented" inventory).
2. Invoke the `flutter-knowledge` skill — authority on architecture/conventions.
3. Then read this file's Part A above, the PNGs, and the actual repo files this brief
   references (`manual_connect_screen`, `AppSheetChrome`, `AppDialog`, `PrimaryButton`).

**Target feature — exact path (non-negotiable):**
`lib/feature/pairing/presentation/connections_screen/` — **this directory does not exist
yet**, create it following this project's standard screen shape (`ui/`, `ui/widgets/`,
`logic/` with a Cubit — see `flutter-knowledge`). Every file for this screen and its 3
sheets/dialogs goes under this path.

**Already exists — do NOT recreate:**
- `lib/feature/pairing/presentation/manual_connect_screen/` already has a form
  cubit/logic for name+address input. **Reuse its cubit/validation logic for the add/edit
  sheet's form** rather than writing a second, parallel form implementation — read it
  first to see what's reusable as-is vs. what needs a thin adapter (the sheet's UI shape
  differs from `manual_connect_screen`'s presumably full-screen shape, but the
  data/validation layer shouldn't be duplicated).
- `AppSheetChrome`, `AppDialog`, `PrimaryButton` (Phase 5 core widgets) — build the 3
  sheets/dialogs on top of these, don't hand-roll scrim/container markup.

**Files to create:**
- `connections_screen/logic/connections_cubit.dart` + state — holds the list of saved
  connections (dummy data for now) and connecting-row state.
- `connections_screen/ui/connections_screen.dart` — the screen body per Part A.
- `connections_screen/ui/widgets/connection_row.dart`, `connection_menu_sheet.dart`,
  `connection_form_sheet.dart` (wraps/reuses `manual_connect_screen`'s form logic),
  `remove_connection_dialog.dart`.
- Router/DI wiring: add a route + `ServiceLocator` entry per this project's convention.

**Key implementation points:**
1. Fix the pre-fill quirk noted in Part A — edit mode must populate the form fields from
   the tapped connection.
2. The connecting-row auto-navigate-after-delay is a prototype stub — wire it to real
   pairing/connection state instead of a fixed timer once a backend exists; for this
   UI-only pass, a timer stand-in matching the prototype's visual is acceptable but should
   be clearly marked as temporary (e.g. a `// TODO` — check this project's convention on
   whether TODOs are allowed, per `flutter-knowledge`).
3. The "Remove desktop" button needs a danger-styled trailing button (`red` background,
   white text) — extend `AppDialog` with this variant if it doesn't already support one,
   rather than bypassing `AppDialog`.
4. "Pair a new desktop" and the header info both route to the pairing flow
   (`pairing_scan_screen`), matching onboarding's "Pair Desktop" destination.

**Dummy data:** the 2 connections verbatim from Part A ("Alex's MacBook Pro" /
100.94.12.3 / 2h ago; "Office iMac" / 192.168.1.42 / 3d ago).

**Localization:** this project's CLAUDE.md overrides the generic Flutter convention —
**no `LocaleKeys`/easy_localization**, inline English strings only.

**Definition of done:**
- `flutter analyze` clean.
- Matches all 6 screenshots in both themes (dark is the captured default; verify light
  too using `colors.md`'s light-theme tokens).
- Row tap, "⋮" menu, add/edit sheet (with correct pre-fill), and remove dialog all work
  as specified above, including the pre-fill fix.
- Files live only under `lib/feature/pairing/presentation/connections_screen/`.
