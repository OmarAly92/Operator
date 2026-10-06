# Mobile chat polish, T3-inspired

Date: 2026-09-24. Branch: `feat/mobile-ios-polish` (worktree
`/Users/omaraly/development/AI/Operator-ios-polish`). Package: `packages/mobile`.

## Why

The session chat screen (`TerminalBody` in blocks mode) is the only screen with no glass.
- Its header and composer dock are opaque `bgChrome` bars (`terminal_chat_header.dart:34`,
  `terminal_body.dart:111`).
- Its only motion is the assistant-reply fade (`incoming_response.dart`, 260ms).
- Tool and thinking disclosures snap open (`block_card.dart:430-490, 569-645`).
- Jump-to-latest is a plain accent circle (`block_nav_controls.dart`).

The user compared it with the T3 mobile app (`/Users/omaraly/development/AI/t3code/apps/mobile`,
screenshots in `t3-mobile-screenshots/dark`). They asked for all nine ideas below, "best UI and
smooth, good animation". The ideas are taken from T3, not copied from it.

## Decisions (user, 2026-09-24)

| Decision | Choice |
|---|---|
| Scope | All nine ideas. |
| Design authority | The controller decides the details. The user reviews the finished UI on the simulator and asks for changes. |
| Other session's uncommitted mobile work (header, block list, block card, session card) | Land it on `development` first, merge it here, then edit those files. Until then only the files it does not touch are edited. |
| Colours | Operator's skin. Glass changes the material, not the colours. |

## Design

### 1. Glass composer (`terminal_composer.dart`, `terminal_body.dart`)

- **Layout.** The opaque dock becomes a floating glass capsule over the content.
  - The body is a `Stack`: the content fills the screen, and the dock floats at the bottom.
  - The capsule is 8pt in from the sides. It sits 8pt above the keyboard when the keyboard is up, and on the bottom safe area otherwise, as T3 does.
  - Content scrolls under the capsule. The list's bottom padding is the dock's measured height plus 12pt.
- **The capsule** is a `GlassSurface` capsule, 48pt at rest, with the same material as the approved sheet search capsule.
  - Leading: a 36pt ⚡ session-actions button. It is hidden for shell-only sessions.
  - Middle: the text field, `style17Regular`, with a "Message the agent…" / "Send to terminal…" hint.
  - Trailing: one 36pt round action that cross-fades (`AnimatedSwitcher`, 160ms, scale 0.8→1 plus fade) between three states:
    - **Mic**: the text is empty and the session is idle. This is today's `MicKey`.
    - **Send**: there is text. An accent circle with an up arrow.
    - **Stop**: the text is empty and the session is working. A red circle with a stop square, placed left of the mic, which stays so dictation still works. It interrupts the current turn (`SessionCommandCubit.run('stop')`), with no confirm. Kill stays in the ⚡ menu.
  - A live recording always keeps the mic in place.
- **Expanding.** When the field has focus and holds 2+ lines, or contains a newline, the capsule morphs into a card.
  - Card radius 26, up to 5 lines tall.
  - A toolbar row appears below the text, holding the model chip (`ProviderIcon`-style harness glyph, model label and a chevron) and send.
  - The morph animates height and radius together over 220ms `AppMotion.easeOut`.
  - The chip opens the existing model picker.
  - Collapsing reverses the morph.
- **Above the capsule**, stacked with 8pt gaps, fading in and out over 180ms:
  - the voice strip, slash menu, suggested-prompt bubble and subagent strip
  - the key row in terminal mode
  - They float on glass rather than an opaque dock.
- **Hide keyboard.** The keyboard-dismiss chevron moves into the expanded toolbar.

### 2. Glass header (`terminal_chat_header.dart`)

- **Background.** The header becomes transparent, and content scrolls under it.
  - Behind it sits a frosted band using `FrostedMaterial`, the approved sheet frost.
  - The band fades in over the first 16pt of scroll, with a hairline bottom edge, like the sheet header.
  - At rest, over the top of the list, the header is clear.
- **Leading.** The glass back button (`GlassButton.icon`, 38pt).
- **Title block.** The title and live dot (`style17Bold`), with the subtitle line (harness · project) under it.
  - The model label moves to the composer chip.
- **Trailing.** One glass capsule grouping the activity pill, search and terminal toggle, as T3 groups terminal, files and git.
- **Height and insets.** The header's height (safe top plus 52pt) becomes the list's top padding.

### 3. Floating working control (`blocks_body.dart`, new `floating_working_control.dart`)

- **Placement.** A small glass capsule centred 10pt above the composer.
- **Working pill.** While the session works, the capsule shows "Working 12s", with the timer ticking each second.
  - The label shimmers.
  - The capsule's width animates to its label (240ms, `Cubic(0.33,1,0.68,1)`).
- **Jump to latest.** When the user scrolls up (the list is not pinned), a 38pt glass ↓ chevron slides out to the right of the pill over 240ms.
  - With no pill, the chevron appears alone, centred, with a 180ms fade and scale.
  - Tapping it animates to the latest message and fires `Haptics.select()`.
- **Replaces.** This control replaces `BlockNavControls`' accent button.

### 4. Messages (`block_list.dart`, `block_card.dart`, `incoming_response.dart`)

- **Fresh-only fade.** The reply fade becomes 220ms and applies only to blocks created in the last 3 seconds, so opening an old session does not animate.
- **User bubble.** Radius 20 and maximum width 85% of the content width. Under it sits a right-aligned meta row: the time (`mono10p5`) and a 28pt copy button with a 13pt icon.
- **Assistant reply.** No bubble. Once its turn has settled, a left-aligned meta row shows copy and time. It is hidden while streaming.
- **Copy.** It copies the block text, fires `Haptics.tap()`, and swaps the icon to a check for 1.2s.

### 5. Turns and disclosures (`block_list.dart`, `block_card.dart`, `turn_group_status.dart`)

- **Turn fold.** A settled turn with tool or reasoning blocks shows "Worked for 13s ›" above its final reply.
  - The label comes from `TurnGroup.durationMs`, or from `completedAt - startedAt`.
  - Collapsed is the default. Collapsed hides that turn's tool and reasoning blocks and keeps the user prompt and the final assistant reply.
  - Tapping it expands the turn.
  - A running turn is never folded.
- **Disclosure motion.** Every disclosure animates: the turn fold, tool groups, and the reasoning and tool blocks.
  - The chevron rotates over 180ms.
  - The body grows with `AnimatedSize` and `SizeTransition` over 180ms `AppMotion.easeOut`, with a content fade in over 140ms and out over 120ms.
  - Each toggle fires `Haptics.select()`.
- **Thinking row.** While a turn is running and its latest block is reasoning or no block has streamed yet, a "Thinking" row with a shimmer shows under the last block.
  - Shimmer: a 1350ms linear gradient sweep, then a 1450ms pause, repeating.
  - It stops under reduce motion, and when the route is not visible (`TickerMode`).

### 6. Motion and haptics, shared

- **`AppMotion` constants.** Everything above uses named constants: `chatReply` 220, `disclosure` 180, `disclosureIn` 140, `disclosureOut` 120, `control` 240, `composerMorph` 220, `shimmerSweep` 1350 and `shimmerPause` 1450.
- **`Shimmer` widget.** A `ShaderMask` with a moving linear gradient over its child, reused by the Thinking row and the working pill.
- **Streaming haptic.** `Haptics.select()` when a reply starts streaming, then at most every 320ms while its text grows. It is off under reduce motion.
- **Reduce motion.** Every animation respects `MediaQuery.disableAnimations`: durations drop to zero and the shimmers stop.

## Behaviour that must not change

- **Sending and routing.** Send, model commands, the terminal send target, voice dictation and the kill confirm behave exactly as today.
- **Scrolling.** The list stays pinned to the bottom while streaming. Scrolling up unpins it, and jump-to-latest re-pins it. Pinning is `block_list.dart:289-315`, and it must stay.
- **Search and selection.** Find, selection mode, rollback and the block action sheet keep working.
- **Terminal mode.** Terminal mode (`RawTerminalPane`) keeps its key row. Its content does not scroll under the composer; it ends above the dock.

## Testing

- **Widget tests.**
  - The composer: the three trailing states, expand and collapse, and stop running the kill confirm.
  - The list insets: the first message is below the header, and the last message clears the composer.
  - The working control: the pill appears only while working, and the chevron only when unpinned; tapping the chevron re-pins the list.
  - Fresh-only fade.
  - Copy and time rows.
  - Turn fold: collapsed by default when settled, never while running, and expands.
  - Disclosures animate: the size is mid-way at half the duration.
  - Shimmer stops under reduce motion.
  - Streaming haptic throttle.
- **Gate.** `flutter analyze` prints "No issues found!", and `flutter test` passes, run from `packages/mobile`.
- **Simulator.**
  - Screenshots in light and dark: the chat at rest, scrolled under the header, the expanded composer, working with the pill and the Thinking row, and an expanded turn.
  - Burst frames of an expand and a composer morph, checked for jumps.

## Out of scope

- Markdown rendering changes.
- The raw terminal renderer.
- Attachments: T3's **+** attach menu. Operator has no upload path.
- Swipe-back gestures.
