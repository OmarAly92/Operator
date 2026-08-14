# Task 22 Report: Chat Timeline

## Status

Completed on `worktree-flutter-mobile-m3`.

Task 22 now provides the multi-widget Flutter chat timeline layer, activity metadata and run grouping, expandable activity details, file-change and plan cards, turn summaries with guarded rollback, message and system-item rendering, conversation-map jumps, and the 120-logical-pixel tail-follow behavior.

All eight Task 22 checkboxes are marked complete in both the local task brief and the canonical milestone plan.

## Requirements and source review

The implementation was derived from:

- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-22-brief.md`
- `packages/mobile_rn/lib/chat/ChatTimeline.tsx`
- `packages/mobile/lib/feature/chat/data/model/activity_detail_model.dart`
- `packages/mobile/lib/feature/chat/data/model/conversation_item_model.dart`
- `packages/mobile/lib/feature/chat/data/model/conversation_snapshot_model.dart`
- `packages/mobile/lib/feature/chat/data/model/conversation_turn_model.dart`
- `packages/mobile/lib/feature/chat/logic/ansi.dart`
- `packages/mobile/lib/feature/chat/logic/timeline_model.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_atoms.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_markdown.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/highlighted_code_text.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/approval_card.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/user_input_card.dart`
- The app skin, text-style, text, and spacing wrappers used by neighboring chat widgets

The assigned checkout was already a linked worktree on `worktree-flutter-mobile-m3`, with no pre-existing changes.

## TDD evidence

### Baseline

Command:

```text
cd packages/mobile
flutter test
```

Result:

```text
00:17 +574: All tests passed!
```

### RED: required Task 22 test

The brief's required timeline test was created before production files.

Command:

```text
flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart
```

Observed failure:

```text
Error when reading 'lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart': No such file or directory
Error when reading 'lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart': No such file or directory
Error: Method not found: 'ChatTimeline'.
Error: Method not found: 'summarizeActivities'.
00:00 +0 -1: Some tests failed.
```

This was the intended RED: the Task 22 public API and widgets did not exist.

### GREEN: required Task 22 test

After the first minimal implementation:

```text
00:00 +9: All tests passed!
```

### RED/GREEN: initial tail following

A focused regression was added for the requirement that a newly mounted long timeline begins at the latest exchange.

First observed RED:

```text
Expected: <3024.25>
Actual: <0.0>
```

The first post-frame correction then revealed lazy-list extent growth:

```text
Expected: <3306.0>
Actual: <3024.25>
```

The final implementation listens for scroll-metric changes while tail following and re-pins after the lazy list establishes its final extent.

Focused GREEN:

```text
00:00 +1: All tests passed!
```

### RED/GREEN: distant conversation-map jump

A focused regression was added for jumping to a group that had not yet been lazily constructed.

Observed RED:

```text
Expected: exactly one matching candidate
Actual: Found 0 widgets with text containing Mapped answer 20
```

The implementation now scrolls toward the requested group, retries after layout, and calls `Scrollable.ensureVisible` once the group's `GlobalKey` has a context. It acknowledges the jump once, after success or bounded exhaustion.

Focused GREEN:

```text
00:00 +1: All tests passed!
```

### Final focused suite

Command:

```text
flutter test test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart
```

Result:

```text
00:01 +15: All tests passed!
```

The 15 tests cover:

- Empty-conversation invitation
- Human and assistant message rendering
- Unconfirmed delivery copy
- Consecutive mechanics collapsing
- Failed activity default expansion
- Turn plan progress and state
- Rollback capability gating
- Rollback confirmation before daemon invocation
- Earlier-history affordance
- Initial tail positioning on long timelines
- Distant conversation-map jumps
- The 120-pixel `Latest` affordance and return to tail
- Command-category summaries
- Non-foldable human-visible activity boundaries
- MCP tool, auto-review, plan, and plural summaries

## Implementation

### Activity layer

- `ActivityMeta` maps command, file-change, MCP, auto-review, and fallback activities to skin-aware icons and colors.
- `summarizeActivities` preserves the React Native read/search/version-control/command/tool/review/plan categorization and singular/plural wording.
- `activityRuns` collapses only consecutive runnable mechanics in the same turn.
- Approval, elicitation, error, file-change, reasoning, and event-bearing activities remain individual rows.
- Nested provider activity relationships use the existing `activityHierarchy`, `countActivityNodes`, and `activityNodesRunning` logic.

### Timeline items

- Human messages use the right-aligned delivery-aware bubble.
- Assistant messages reuse `ChatMarkdown` and expose the copy action.
- Non-human user-origin messages render as expandable reports.
- Approval and elicitation items delegate to the existing Task 21 cards.
- Compaction, steer, reroute, reauthentication, and error activities retain dedicated visual treatment.
- Command output uses the existing ANSI stripping and caret-notation helpers.

### Plans, files, and turn summaries

- Activity plans and turn plans share `PlanShell`.
- `TurnPlanCard` and `ChangedFilesCard` satisfy the public Task 22 widget surface.
- `FileChangeList` is shared by activity-level and turn-level file rendering.
- Patch blocks reuse `HighlightedCodeText` and support long-press copy.
- Turn rollback is shown only after existing `canRollbackTurn` capability checks and local settled/id checks.
- Rollback requires explicit confirmation and surfaces callback failures without altering file state.

### Scrolling and navigation

- `ChatTimeline` uses `ListView.builder` over `groupConversationByTurn`.
- Each group receives a stable `GlobalKey`.
- Initial and update-time tail following account for Flutter lazy-list metric changes.
- Moving more than 120 logical pixels from the tail exposes `Latest`; selecting it returns to the true end.
- Distant map targets are approached proportionally until their lazy anchor exists, then finalized with `Scrollable.ensureVisible` at alignment `0.18`.

## Files changed

Created production files:

- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_meta.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_row.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/activity_run.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/file_change_list.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/plan_card.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/turn_summary.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/timeline_item.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_timeline.dart`

Created test file:

- `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_timeline_test.dart`

Updated plan files:

- `docs/superpowers/plans/2026-08-13-flutter-mobile-port-m3.md`
- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-22-brief.md`

Created report:

- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-22-report.md`

## Final verification

Mandated command:

```text
flutter analyze && flutter test
```

Result:

```text
Analyzing mobile...
No issues found! (ran in 2.2s)
00:16 +589: All tests passed!
```

The milestone brief's expected count is stale because the assigned baseline already contained 574 tests rather than 551. Task 22 adds 15, producing the verified total of 589.

No app launch or build command was run, as instructed.

## Self-review

### Clean-code guard

- Read the edited feature neighbors and project rules before writing.
- Kept daemon/model logic out of presentation widgets and reused existing timeline logic.
- Added no dependency, persistence, networking, or speculative abstraction.
- Added no production comments, raw color literals, raw text styles, or feature-level ScreenUtil usage.
- Reused skin colors, `AppTextStyle`, `AppText`, and spacing wrappers.
- Changed generic activity detail rendering from dynamic access to `ActivityDetailModel`.
- Catches are limited to JSON serialization fallback and user-visible async rollback failure reporting.
- No hardcoded success payloads, dead imports, disabled tests, or unrelated cleanup remain.
- `flutter analyze` and `git diff --check` are clean.

### Test guard

- Tests exercise real widgets and pure functions; no mock objects were introduced.
- Assertions target user-visible copy, scroll position, rendered boundaries, and callback outcomes.
- Rollback tests assert the real confirmation boundary before the callback can run.
- Activity grouping tests construct real immutable models and assert row behavior rather than internal helper calls.
- No framework guarantees, snapshots, source-text checks, or duplicate value-only cases were added.

### Mutation check

The focused tests fail for realistic regressions including:

- Removing the empty invitation or delivery warning
- Rendering mechanics separately instead of collapsing them
- Folding approval, file-change, or event-bearing activities
- Losing command categorization or pluralization
- Hiding failed output by default
- Omitting plan progress/state
- Showing rollback without daemon capability
- Invoking rollback before confirmation or with the wrong turn id
- Ignoring earlier-history availability
- Mounting a long timeline at the beginning
- Failing to materialize a distant map target
- Changing/removing the 120-pixel tail-follow behavior

## Concerns

No implementation blockers or unresolved correctness concerns remain. The only discrepancy is the stale expected test count in the written brief; current repository evidence is 589 passing tests.
