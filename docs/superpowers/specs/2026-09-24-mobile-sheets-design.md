# Mobile sheets, T3 design

Date: 2026-09-24. Branch: `feat/mobile-ios-polish` (worktree
`/Users/omaraly/development/AI/Operator-ios-polish`). Package: `packages/mobile`.
This revises part 4 ("Sheets") of `2026-09-24-mobile-glass-chrome-design.md`.

## Why

The first pass made every sheet a floating glass panel (plan Task 5). On the device the user
rejected it and pointed at the T3 mobile app instead (`/Users/omaraly/development/AI/t3code`,
`apps/mobile/src/Stack.tsx`):
- T3's sheets are iOS form sheets, `presentation: "formSheet"` with `sheetGrabberVisible: true`.
- Each has a navigation bar inside the sheet.
- They use detents such as `[0.55, 0.92]` or `[1]`.

The user wants that design in Operator's own colours, including the search capsule and pages
pushed inside a sheet.

## Decisions (user, 2026-09-24)

| Decision | Choice |
|---|---|
| App bar | Leave as built in Task 2 for now. |
| Tab bar and + | Keep as built in Task 4. |
| Sheet design | T3's: opaque surface, floating inset, grabber, header with a centred title, glass back and action buttons. Operator's colours. |
| Search capsule | In the project, agent and Claude account pickers. |
| Second page | A reusable page stack. It is used by the connection menu (Rename becomes a page) and by Spawn (one sheet with project, agent and account pages). |

## Design

### The sheet surface

- The surface is `skin.bgSurface`, opaque. It is not glass.
- The sheet floats `GlassMetrics.sheetInset` (8pt) in from the left, right and bottom at every
  height. It is never edge-anchored.
- Corners: `RoundedSuperellipseBorder`, radius `GlassMetrics.displayCornerRadius -
  GlassMetrics.sheetInset` (56), which is concentric with the display.
- A grabber sits at the top (36×5, `skin.borderStrong`).
- The barrier is `GlassSheetLogic.barrierColor(skin)`, unchanged.
- Height is one of three detents:
  - `fit`: sizes to the content, up to the large height. Animated between pages.
  - `medium`: 0.55 of the screen height.
  - `large`: 0.92 of the screen height.
- Every detent is clamped so the sheet stays below the status bar and above the keyboard.

### The header

- One row, 44pt tall, below the grabber.
- The title is centred, `AppTextStyle.style17Bold`, one line, ellipsized.
- The leading slot holds the glass back button (`GlassButton.icon`,
  `Icons.arrow_back_ios_new_rounded`, `skin.textPrimary`). It shows only on a pushed page.
- The trailing slot holds actions, each in a `GlassBarItem`, as in the app bar.
- The page's content scrolls under the header. A fade from `bgSurface` with a light blur keeps
  the title legible over it. This is not the black scroll-edge effect, which greys flat
  backgrounds.

### The search capsule

- A page may declare a search hint. The sheet then shows a floating glass capsule, 48pt tall,
  16pt from the sheet's sides and 12pt from its bottom.
- The capsule holds a search icon and a text field.
- The typed query is passed to the page's builder, which filters its rows.
- Content clears the capsule.
- A query that matches nothing shows "No matches".
- Filtering is case-insensitive substring matching over the fields each picker names.

### Pages

- A sheet opens on a root page and can push further pages.
- Push and pop slide horizontally inside the sheet. The header's title and back button follow
  the top page.
- A page may pop itself, or close the whole sheet with a result.
- Pages below the top are not kept alive. A pushed-then-popped page rebuilds from its builder,
  and its search query resets.
- A sheet may open with pages already pushed above its root, which is how Spawn opens directly
  on one picker.

### Uses

- **Theme picker.** Title "Theme". Single page, `fit`.
- **Project picker**, from the Agents tab switcher and from Settings. Single page, `large`. The
  search hint is "Search projects", matching on name, id and session prefix.
- **Connection menu.** Title is the desktop name, `fit`.
  - Rename pushes a "Rename desktop" page in the same sheet, with the name field and Save.
  - Save closes the sheet with the new name.
  - Remove closes the sheet and runs today's confirm dialog.
  - The separate rename sheet is deleted.
- **Spawn.** One sheet, `large`.
  - The root page, "Spawn options", lists Project, Agent and Claude account with their current
    values.
  - Each row pushes its picker page. Picking updates the spawn form at once and pops back to
    the root.
  - "Done" in the root header closes the sheet.
  - Tapping the Project, Agent or Account row on the Spawn screen opens the sheet with that
    row's page already pushed.
  - The picker pages have search:
    - "Search projects": name, id, session prefix
    - "Search agents": label, id
    - "Search accounts": label, id, plan label
  - The Agent page's Refresh becomes a header action.
  - The standalone agent and Claude account sheets are deleted.

## Behaviour that must not change

- Every picker still reports the same value to its caller. The theme picker, project picker
  and connection menu return the same results.
- Selection haptics are unchanged: `Haptics.select()` once per pick.
- Rename trims the name, and Save stays disabled while the name is empty.

## Testing

- **Widget tests for the sheet:**
  - opaque floating surface
  - grabber
  - centred title
  - back button only on pushed pages
  - push, pop and close with a result
  - `fit` sizes to the content
  - the detents are clamped under the keyboard
  - search filters, and shows "No matches"
  - content starts below the header and clears the capsule
- **Unit tests** for the filter function.
- **Flow tests:**
  - the connection menu's rename page returns the name, and its remove result is unchanged
  - Spawn's sheet opens on the tapped page, and picking updates the cubit and pops to the root
- **Gate:** `flutter analyze` and `flutter test` from `packages/mobile`.
- **Screenshots** from the simulator in light and dark:
  - the theme sheet
  - the project picker with a query
  - the connection menu and its rename page
  - the Spawn sheet on its root and on the Agent page

## Out of scope

- Detents the user can drag between; each sheet has one detent.
- Swipe-back between pages; the back button pops.
- The four `showModalBottomSheet` sheets (session actions, block actions, model picker,
  subagent strip).
