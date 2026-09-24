# Mobile Chat Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the session chat screen T3-inspired glass chrome, message details and smooth motion.

**Architecture:** Shared motion pieces come first: `AppMotion` constants, `Shimmer`, `DisclosureChevron`/`Disclosure` and streaming haptics. Then comes the composer and body layout, which sits in files no other session touches. The header, working control, messages and turn fold follow once the other session's mobile work has merged into this branch.

**Tech Stack:** Flutter 3.44.5, flutter_bloc cubits, the project's glass engine (`lib/core/widgets/glass/`).

**Spec:** `docs/superpowers/specs/2026-09-24-mobile-chat-polish-design.md`

## Global Constraints

- **Location.** Work only in `/Users/omaraly/development/AI/Operator-ios-polish`, on branch `feat/mobile-ios-polish`. Never touch `/Users/omaraly/development/AI/Operator`.
- **No code comments** in anything you author. Keep upstream comments that already exist in the files you edit.
- **Commit trailer.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Check it with `git log -1 --format=%B | grep -c "Co-Authored-By: Claude Opus 5.5"`.
- **Gate.** Run from `packages/mobile`: `flutter analyze` prints "No issues found!" and `flutter test` passes. Never weaken an existing test.
- **Never stage** `frontend/package-lock.json`.
- **Package conventions.** Cubit only. Feature code does not import `flutter_screenutil`. Copy is inline English.
- **Locked files.** Until the ledger records "other-session work merged", do not edit:
  - `terminal_chat_header.dart`, `block_list.dart`, `block_card.dart`, `session_card.dart`
  - `activity_string.dart`, `session_model.dart`
  - their tests
- **Motion.** All durations and curves are named `AppMotion` constants. Every animation respects `MediaQuery.disableAnimationsOf(context)`.
- **Visual claims** need a simulator screenshot: iPhone 17 Pro, UDID 94D0C207-A90B-4806-BBAB-8AF9B3F16329. Build with `flutter build ios --simulator --debug` and capture with `xcrun simctl io <udid> screenshot`.

## Review Focus

1. **Keyboard up while the composer is expanded.** The composer sits on the keyboard, and the list's last message stays visible above it.
2. **Streaming while the user is scrolled up.** No auto-jump, and the chevron stays. Streaming while pinned stays pinned as the composer grows.
3. **Reduce motion.** No animation runs, and the shimmers are static.
4. **Shell-only sessions.** No ⚡, no stop, no model chip, and no working pill beyond what the session supports.
5. **Old sessions with hundreds of blocks.** No fade on load, and the fold state is stable while scrolling.

---

### Task 1: Motion foundations

**Files:**
- Modify: `lib/core/app_themes/app_motion.dart`
- Create: `lib/core/widgets/motion/shimmer.dart`, `lib/core/widgets/motion/disclosure.dart`, `lib/core/utils/streaming_haptics.dart`
- Test: `test/core/widgets/motion/shimmer_test.dart`, `test/core/widgets/motion/disclosure_test.dart`, `test/core/utils/streaming_haptics_test.dart`

**Produces:**
- **`AppMotion` constants:** `chatReply` (220ms), `disclosure` (180ms), `disclosureIn` (140ms), `disclosureOut` (120ms), `control` (240ms), `controlCurve` (`Cubic(0.33, 1, 0.68, 1)`), `composerMorph` (220ms), `shimmerSweep` (1350ms), `shimmerPause` (1450ms), `chatActionSwap` (160ms), `streamingHapticGap` (320ms).
- **`Shimmer({required Widget child, required Color base, required Color highlight, bool enabled = true})`**
  - A `ShaderMask` with a linear gradient band moving left to right over `shimmerSweep`, then a pause for `shimmerPause`, repeating.
  - It renders the static child when disabled, under reduce motion, or when `TickerMode` is off.
- **`DisclosureChevron({required bool expanded, double size = 14, Color? color, double collapsedTurns = 0, double expandedTurns = 0.25})`**: an `AnimatedRotation` over `disclosure`.
- **`Disclosure({required bool expanded, required Widget child})`**
  - `ClipRect`, `AnimatedSize` over `disclosure` with `easeOut`, and `AnimatedSwitcher`/`AnimatedOpacity` with a fade in over `disclosureIn` and out over `disclosureOut`.
  - When collapsed it renders `SizedBox.shrink`. It keeps the child's state while expanded.
- **`StreamingHaptics`**
  - Takes an injectable `void Function() fire` and an injectable clock.
  - `onStreamStart()` fires once.
  - `onTextGrew()` fires at most once per `streamingHapticGap`.
  - `enabled` is false under reduce motion.

- [ ] Write failing tests.
  - Shimmer: the gradient transform changes between pumps while enabled, and is static when `disableAnimations` is true.
  - Chevron: at half the duration its rotation is between the two turn values.
  - Disclosure: at half the duration the height is strictly between 0 and full, at full duration it is full, and collapsing reaches 0.
  - StreamingHaptics: throttling with a fake clock.
- [ ] Implement, then run the gate and commit: `feat(mobile): chat motion foundations — shimmer, disclosure, streaming haptics`.

### Task 2: Glass composer and floating dock

**Files:**
- Modify: `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`, `.../terminal_body.dart`
- Create: `.../ui/widgets/composer_action_button.dart`, `.../ui/widgets/composer_model_chip.dart`
- Test: `test/feature/terminal/.../terminal_composer_test.dart` (extend the existing tests when present), `terminal_body_layout_test.dart`

**Consumes:** Task 1's `AppMotion` constants, and `GlassSurface`/`GlassButton` from `lib/core/widgets/glass/`.

Implement spec §1.
- **Body layout.** `TerminalBody` becomes a `Stack`:
  - The content is full-bleed in blocks mode. In terminal mode the pane ends above the dock.
  - The dock is `Positioned` at the bottom, above the keyboard.
  - The dock's measured height is published through an `InheritedWidget` or `ValueNotifier`, e.g. `ChatInsets` in `lib/feature/terminal/presentation/terminal_screen/ui/widgets/chat_insets.dart`, with `bottom`. `BlocksBody` reads it and passes it as the list's bottom padding.
  - `BlocksBody` and the list padding are not locked. If the padding is applied inside `block_list.dart`, which is locked, pass it through `BlocksBody` as `MediaQuery.padding` instead.
- **Model chip.** Its label comes from the same source as the header's `_SessionModelLabel`: `SessionCommandCubit.currentModel` plus the harness default. Read that widget's logic and reuse it through a shared function in a new file, without editing the locked header. The header keeps its label until Task 3.
- **Stop state.** "Working" comes from the source the header pill uses. Find it read-only and reuse it the same way. Stop calls the body's existing `_confirmKill`, passed down as a callback.
- [ ] Tests:
  - the trailing states: mic when empty and idle, send when there is text, stop when empty and working, and none for shell-only
  - stop invokes the kill callback
  - expanding when there is a newline or two lines while focused: the height grows and the chip appears; clearing the text collapses it
  - the last list item's bottom is at or above the composer's top when scrolled to the end
- [ ] **Simulator.** Screenshots at rest, expanded, with the keyboard up (use `xcrun simctl` with a hardware keyboard: focus shows no software keyboard, and that is acceptable), and in the light and dark themes. Save them to `packages/mobile/build/chat-polish/t2/`.
- [ ] Commit: `feat(mobile): floating glass composer that grows into a card, with stop and model chip`.

### Task 3: Glass header (requires merged other-session work)

**Files:**
- Modify: `terminal_chat_header.dart`, `terminal_body.dart`
- Test: the header test file

Implement spec §2.
- The header floats in the body `Stack` over the content, with a `FrostedMaterial` band whose visibility follows the list's scroll offset over the first 16pt, plus the hairline, as in `app_sheet.dart`'s header band. Reuse its visibility logic and extract it if needed.
- The model label is removed from the header; the Task 2 chip owns it.
- `ChatInsets.top` is the header height, and the list pads its top by it.
- [ ] Tests: the header is transparent at rest and the band is visible after scrolling 16pt; the back button and grouped trailing capsule; the first message is below the header.
- [ ] Take simulator screenshots, then commit.

### Task 4: Floating working control (requires merged other-session work)

**Files:**
- Create: `lib/feature/blocks/presentation/blocks_screen/ui/widgets/floating_working_control.dart`
- Modify: `blocks_body.dart`, `block_nav_controls.dart` (remove its button, or delete the file if it becomes unused)
- Test: `floating_working_control_test.dart`

Implement spec §3. The elapsed time reuses `turnElapsed`/`activeSince` from the merged work.
- [ ] Tests: the pill shows only while working, and the chevron only when unpinned; tapping the chevron calls `jumpToLatest` and fires a haptic; the width animates.
- [ ] Take simulator screenshots, then commit.

### Task 5: Message rows (requires merged other-session work)

**Files:**
- Modify: `incoming_response.dart`, `block_list.dart`, `block_card.dart`
- Create: `message_meta_row.dart`
- Test: the existing block_list/block_card tests plus `message_meta_row_test.dart`

Implement spec §4, plus the streaming haptic from §6 (it uses `StreamingHaptics`, hosted in `BlockListState` where `_pendingResponses` is computed).
- [ ] Tests: fresh-only fade (a block created 10s ago renders without `IncomingResponse` animating); the meta rows and the copy check swap; assistant meta is hidden while streaming; the haptic throttle is wired.
- [ ] Take simulator screenshots, then commit.

### Task 6: Turn fold, animated disclosures, Thinking row (requires merged other-session work)

**Files:**
- Modify: `block_list.dart`, `block_card.dart`, `turn_group_status.dart`, `tool_group_header.dart`
- Create: `turn_fold_row.dart`, `thinking_row.dart`
- Test: the corresponding tests

Implement spec §5 with Task 1's `Disclosure`, `DisclosureChevron` and `Shimmer`.
- [ ] Tests:
  - a settled turn is folded by default, a running turn is never folded, and tapping expands it
  - fold state survives scrolling (store it in `BlockListState` by turn id)
  - the Thinking row shows only while running
  - disclosures are mid-size at half the duration
- [ ] Take simulator burst frames of an expand, then commit.

### Task 7: Verification

- [ ] **Screenshots**, light and dark, saved to `packages/mobile/build/chat-polish/final/`:
  - the chat at rest and scrolled under the header
  - the expanded composer
  - working, with the pill and the Thinking row
  - an expanded turn
- [ ] **Burst frames** of a disclosure and a composer morph, checked for jumps.
- [ ] Send the screenshots to the user for feedback.
