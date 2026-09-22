# Split view — design

**Date:** 2026-09-22 · **Status:** approved in chat, awaiting spec review

Drag a session tab, a shell tab, or a sidebar session into the session area to
split it, as Claude Code's desktop app does. Any number of panes, split in any
direction, each with its own tab strip. The measure of success is that Claude
Code and Operator, recorded side by side, are indistinguishable in how splitting
looks, moves and behaves.

The reference is a screen recording of Claude Code made by the user on
2026-09-22 (`video/Screen Recording 2026-09-22 at 10.13.17 PM.mov`, 20.9s,
2724×1824 @120fps, not committed). Frames cited below are in
[`assets/2026-09-22-split-view/`](assets/2026-09-22-split-view/).

## 1. Claude Code fidelity reference (measured)

Everything here was measured from the recording; where the recording does not
show something, this section says so.

| Behaviour | Claude Code | Evidence |
|---|---|---|
| Drag preview | The dragged sidebar row itself — status dot + title, semi-transparent — follows the cursor | `01-drag-row-ghost.jpg` |
| Preview over a target | Cross-fades into a dark rounded chip reading "Open in split view" | `02-ghost-crossfade-over-target.jpg`, `03-…` |
| Drop target | A fixed box exactly **one half** of the hovered pane: ~2px blue rounded outline, content inside **blurred**, a blue filled **"Split view" pill** centred in the box | `03-target-box-blur-pill.jpg` |
| Rest of window during drag | Slightly dimmed, sharp | `01`, `03` |
| Moving between halves | The box **slides**; it does not jump. ~100–120ms, strong ease-out. Measured left edge at 60fps: 834 → 650 → 500 → 418 → 348 → 326 → 318 → 316 px | frame analysis, 0.617–0.733s |
| Box appear / disappear | Within one captured frame (<60ms): no visible fade | 0.583→0.592s, 2.733→2.742s |
| Edge halves | Left/right half → side-by-side split; top/bottom half → stacked split. 3- and 4-pane layouts were built this way | `05-three-panes.jpg`, `06-four-panes.jpg` |
| Centre of an occupied pane | Replaces that pane's content in Claude Code (Operator adds a tab instead — §2) | `07-centre-drop-replaced.jpg` |
| Drop | The split **snaps** in one frame; halves are equal; no grow/slide animation | 5.13→5.17s |
| Divider | 1px line between panes; no gap, no rounding | `04-two-panes.jpg` |
| Pane header | Title with chevron, folder button; right: icon actions, ⋯, ✕ | `04` |
| Sidebar | Every session shown in any pane is highlighted; hovered row shows ⋯ | `04`, `05` |
| Divider drag, closing a split | **Not shown in the recording.** Divider moves live with no easing; closing snaps and the sibling takes the space | — |

## 2. Behaviour

**Workspace.** One app-wide layout (not per project), persisted locally and
restored on launch. A pane is a leaf holding ordered tabs and an active tab.
Tab kinds: `session` (the agent), `shell`, `reviewer`. Any tab kind can be
dragged on its own; a shell may sit in a different pane from its session.
Sessions may come from any project.

**Focused pane.** The pane last pointer-downed or focused. Only one. It drives:
the route (`/projects/$projectId/sessions/$sessionId` of its active tab's
session), the inspector rail, Cmd+W, ⌥⌘←/→, and where sidebar clicks open.

**Drag sources.** Session, shell and reviewer tabs in any pane's strip; session
rows in the sidebar. 4px activation distance so clicks and the right-click menu
are unaffected (same constraint as the ticket drag today,
`TicketDndProvider.tsx:48`).

**Drop targets**, resolved per pointer move:

- An **edge half** of a pane (left/right/top/bottom) → split that pane in that
  direction; the dragged tab becomes the only tab of the new pane, which is
  focused. The half closest to the pointer wins; halves are the four triangles
  from the pane's centre to its edges, minus the centre region.
- The **centre** region (middle 40% × 40%) or the **tab strip** of a pane →
  move the tab into that pane (at the insertion caret on a strip, else at the
  end) and activate it.
- A half is **not offered** when either resulting pane would be under
  320px wide (side split) or 200px tall (stacked split); the box does not appear.
- Dropping a tab on its own pane's centre or strip with no position change is a no-op.

**One place per tab.** A tab exists in at most one pane. Dragging an open
session from the sidebar moves its tab. A pane emptied by a move is removed and
its sibling takes the space.

**Sidebar click (no drag).** Focus the tab wherever it is open; otherwise add
it to the focused pane.

**Closing.** ✕ on a tab or Cmd+W closes the focused pane's active tab from
view (never kills the agent; shells close as today). A pane's last tab closing
removes the pane. The last pane closing navigates to the project kanban.

**⌥⌘← / ⌥⌘→ and Ctrl+(Shift+)Tab** cycle tabs inside the focused pane
(replacing this branch's cross-session cycling in `SessionView.tsx`).

**Restore.** Tabs whose session or shell no longer exists are dropped on load
and when the workspace query reports them gone; empty panes collapse.

**Kanban and other routes.** Leaving the session route hides the layout; it is
kept. Returning via a sidebar click focuses that tab in the kept layout.

## 3. Architecture

### 3.1 Layout model — `lib/split-layout.ts` (pure, no React)

```ts
type TabRef = { kind: "session"; sessionId: string }
            | { kind: "shell"; handleId: string; sessionId?: string }
            | { kind: "reviewer"; sessionId: string; handleId: string; harness: string };
type Pane   = { type: "pane"; id: string; tabs: TabRef[]; activeTab: number };
type Split  = { type: "split"; id: string; direction: "row" | "column";
                children: LayoutNode[]; sizes: number[] };   // sizes sum to 100
type LayoutNode = Pane | Split;
type Layout = { root: LayoutNode | null; focusedPaneId: string | null };
```

Operations, each `(Layout, …) => Layout`, never mutating: `openTab`,
`focusTab`, `moveTab(tab, target)`, `splitPane(paneId, edge, tab)`,
`closeTab`, `closePane`, `resize(splitId, sizes)`, `focusPane`,
`cycleTab(direction)`, `prune(existing)`.

**Invariants**, checked by `assertLayout` after every operation in tests and in
dev builds:

1. Every tab key appears in exactly one pane.
2. No pane has zero tabs; `activeTab` is in range.
3. No split has fewer than two children; a split's child never has the split's
   own direction when it could be flattened (a row inside a row is merged).
4. `sizes.length === children.length`, each > 0, sum = 100 (±0.01).
5. `focusedPaneId` names an existing pane, or is null only when `root` is null.
6. Ids are unique.

### 3.2 Store — `stores/split-layout-store.ts`

Zustand, holds `Layout`, wraps each operation, persists to `localStorage`
(`opr.splitLayout.v1`) with a version field; an unreadable or invalid stored
layout (fails `assertLayout`) is discarded, never half-loaded. Replaces
`openSessionTabsByProject` and `openSessionTab`/`closeSessionTab` added on this
branch in `stores/ui-store.ts`.

### 3.3 Drop resolution — `lib/split-drop.ts` (pure)

`resolveDrop(pointer, paneRects, stripRects, draggedTab, layout) →
{ kind: "split", paneId, edge, box } | { kind: "move", paneId, index } | null`.
`box` is the rect the overlay animates to. Encodes §2's regions and minimum
sizes. Exhaustively table-tested.

### 3.4 Drag and drop — one app-wide `DndContext`

dnd-kit droppables register with the nearest context, so a second context
around the sidebar would cut ticket drops off from ticket drags
(`Sidebar.tsx:35` uses `useTicketDropTarget`). `TicketDndProvider`
(`components/tickets/TicketDndProvider.tsx:44-73`, mounted at
`routes/_shell.tsx:600`) becomes `AppDndProvider` with a typed payload union
(`plan | tab`) and per-type start/move/end handlers. Ticket behaviour is
unchanged and its tests keep passing untouched. The split handlers ignore
dnd-kit collision and call `resolveDrop` with the pointer from `onDragMove`.

### 3.5 Components

- `SplitWorkspace` — replaces `SessionView`'s single `CenterPane`; renders the
  tree with nested `react-resizable-panels` groups (percent strings, per the
  v4 note at `SessionView.tsx:453`), 1px separators, the inspector rail on the
  right bound to the focused pane.
- `SplitPane` — one pane: header (tab strip styled as Claude Code's pane
  header, pane actions, ✕), its active tab's terminal, focus ring for the
  focused pane (thin blue rounded outline, per `04-two-panes.jpg`).
- `SplitDropOverlay` — rendered once, above panes: dim layer, the sliding box
  (`motion`, already a dependency, ~110ms ease-out tween on x/y/width/height),
  `backdrop-filter: blur()` inside the box, centred "Split view" pill. Mount and
  unmount without fade. Pointer-events none.
- `SplitDragPreview` — `DragOverlay` content: the row/tab ghost, cross-fading
  (≤120ms) to the "Open in split view" chip while a target is resolved.
- `CenterPane` keeps the terminal surface and switching overlay; its tab strip
  moves into `SplitPane`.

### 3.6 Terminals

- **Cache.** `TerminalCacheProvider` holds one `activeRef`
  (`TerminalPane.tsx:76-79`); activating a key parks the previous
  (`:353-359`) and `deactivate` only honours the single active slot (`:404`).
  It becomes a map `slot → key`: activating a key in a slot parks only that
  slot's previous key; the ready/reveal/visible lifecycle (`:449,466,483`)
  keys off "is this key active in some slot". `packages/terminal` is untouched
  (TERMINAL.md §3).
- **One place per key.** Enforced by the layout invariant 1; the cache also
  refuses (dev assertion) to activate a key already active in another slot.
- **Resize.** Unchanged pipeline: each surface measures its own box
  (`packages/terminal/ts/react/src/TerminalSurface.tsx:231-262`), reflows
  locally every frame, and the pty gets one trailing resize after 100ms still
  (`useTerminalSession.ts:108`). Divider drags therefore cost one SIGWINCH per
  affected pty. Claude Code's upstream duplicate row per width change
  (TERMINAL.md §4.8) is accepted, as for window resizes today.
- **Spawn grid.** `lib/pane-grid.ts` keeps one `lastGrid` from whichever pane
  measured last. Only the **focused** pane records it, since new sessions open
  there (TERMINAL.md §4.5).
- **Focus.** After any layout change only the focused pane's terminal receives
  the focus token (`TerminalPane.tsx:901-905`); others are visible but not
  focused. A pointer-down or `focusin` in a pane focuses it.
- **Notifications.** `visibleTerminalKindBySession` (`ui-store.ts:91`) is
  already per session; each visible pane publishes its active tab.
- **Drag blur.** Only the overlay uses `backdrop-filter`; terminals do not
  re-render during a drag.

## 4. Testing — how bugs are kept out

1. **Model property test.** A seeded random sequence of 10 000 operations over
   a pool of tabs; `assertLayout` after each; plus round-trip through the
   persisted JSON. Any failure prints the seed and the shortest failing prefix.
2. **Drop resolution table tests.** Every region of a pane, both split
   directions, minimum-size refusals, strip insertion indices, self-drop no-op.
3. **Store tests.** Persistence, versioning, corrupt-storage discard, prune on
   missing sessions/shells, focus and route sync.
4. **Terminal cache tests.** Two slots active at once; moving a key between
   slots; parking only the replaced slot; refusal to double-activate.
5. **Component tests** (Vitest + Testing Library): drag a sidebar row and a
   tab onto each region with dnd-kit's pointer sensor; Cmd+W, ⌥⌘←/→, close to
   kanban; ticket drag still assigns a plan.
6. **Real-app verification.** The renderer in the browser pane against an
   isolated daemon with two real sessions, then the Tauri app. Recorded at
   120fps next to the reference recording: box slide timing, snap on drop, no
   terminal flicker, no duplicate transcript, one resize per pty per divider
   release. TERMINAL.md §6's recipe for anything touching the terminal.

## 5. Out of scope

Dragging panes between windows; drag-to-reorder whole panes; per-pane
inspectors; mobile.
