# Task 23 Report: The Composer

## Status

Completed on `worktree-flutter-mobile-m3`.

Task 23 now provides the stateful chat composer, injected attachment-picker seam, production `image_picker` and `file_selector` implementation, skill and worktree-file suggestion sheet, session-scoped draft cache, provider capability gating, steer-versus-queue delivery choice, interruption control, attachment previews, and all specified attachment restrictions.

All eight Task 23 checkboxes are marked complete in both the local task brief and the canonical milestone plan.

## Requirements and source review

The implementation was derived from:

- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-23-brief.md`
- `packages/mobile_rn/lib/chat/ChatComposer.tsx`
- `packages/mobile_rn/lib/chat/composerSuggestions.ts`
- `packages/mobile/lib/core/helpers/cache/cache_helper.dart`
- `packages/mobile/lib/core/helpers/cache/cache_keys.dart`
- `packages/mobile/lib/core/widgets/main_widgets/app_text.dart`
- `packages/mobile/lib/core/widgets/main_widgets/space_widgets.dart`
- `packages/mobile/lib/feature/chat/data/model/chat_attachment_model.dart`
- `packages/mobile/lib/feature/chat/data/model/chat_catalog_model.dart`
- `packages/mobile/lib/feature/chat/data/model/conversation_snapshot_model.dart`
- `packages/mobile/lib/feature/chat/data/model/conversation_turn_model.dart`
- `packages/mobile/lib/feature/chat/logic/composer_suggestions.dart`
- `packages/mobile/lib/feature/chat/logic/keyboard_inset.dart`
- Neighboring chat presentation widgets and the app skin/text-style APIs
- Installed `image_picker` 1.2.3, `file_selector` 1.1.0, and `cross_file` 0.3.5+4 APIs

The assigned checkout was already the linked `worktree-flutter-mobile-m3` worktree with no pre-existing changes.

## TDD evidence

### RED: required Task 23 widget test

The required composer test was created before any Task 23 production implementation.

Command:

```text
cd packages/mobile
flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart
```

Observed result:

```text
Error when reading 'lib/feature/chat/logic/attachment_picker.dart': No such file or directory
Error when reading 'lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart': No such file or directory
Error: Type 'AttachmentPicker' not found.
Error: Type 'PickedAttachment' not found.
Error: Method not found: 'ChatComposer'.
Error: Member not found: 'CacheKeys.chatDraft'.
00:00 +0 -1: Some tests failed.
```

This was the intended RED: the public picker seam, composer widget, and draft cache key did not exist.

### First implementation run and focused diagnosis

The first implementation run passed eight scenarios and exposed one preview-boundary failure:

```text
00:00 +5: attaches an image and forces the message into a new turn
FormatException: Invalid length, must be multiple of four
AAA
00:00 +8 -1: Some tests failed.
```

Root-cause tracing showed that `base64Decode` ran before `Image.memory` was created, so Flutter's `errorBuilder` could not handle malformed provider/test preview data. The minimal correction catches only `FormatException`, renders the existing image placeholder, and preserves the original attachment model for submission.

### GREEN: required Task 23 widget test

Command:

```text
flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart
```

Result:

```text
00:00 +9: All tests passed!
```

The focused tests cover:

- Trimming a sent message and clearing the field after acceptance
- Refusing empty submissions
- Offering steer only for a running, steer-capable provider
- Routing eligible guidance to `onSteer` instead of `onSend`
- Interrupting a running turn when the field is empty
- Sending picked image attachments through `onSend`
- Forcing attachments into the next turn and rendering the exact explanation
- Gating embedded text-file selection on `embedded_context`
- Disabling input for a stopped controller
- Restoring the draft for the current session cache key

## Implementation

### Attachment picker seam

- `AttachmentPicker` isolates live platform-channel operations from widget tests.
- `PlatformAttachmentPicker` uses only the plan-approved `image_picker` and `file_selector` packages.
- Images are base64 encoded into `ChatImageModel`; text files are embedded as `ChatResourceModel` values with `mobile-attachment://` URIs.
- Supported image types are PNG, JPEG/JPG, GIF, WebP, and BMP.
- Per-image size is capped at 10 MB.
- Composer acceptance is capped at eight total attachments and 25 MB of images combined.
- Embedded text is capped at 500 KB with the exact worktree-file alternative copy.
- Picker exceptions preserve exact user-facing restriction strings.

### Composer behavior

- The composer restores and debounces a draft through the existing `CacheHelper` only.
- Draft keys are session-scoped through `CacheKeys.chatDraft`.
- Suggestion triggers are derived from current text and caret in `_onTextChanged` without feeding `_trigger` back into trigger detection.
- Skills and worktree files can be opened from text triggers or toolbar actions.
- Steer eligibility requires a running turn, provider `steer` capability, no prior daemon refusal, queue delivery not selected, and no attachments.
- Any accepted attachment forces queue delivery and explains that attachments start a new turn.
- Empty running-turn input exposes interruption; non-empty input exposes steer or send as appropriate.
- Stopped, pending, or submitting states gate input and submission.
- The selected provider/model label is resolved from provider config, reroute state, or snapshot settings.
- The mic key is absent as required for the M5 deferral.

### Suggestion sheet

- Skill and file choices reuse Task 9 ranking and replacement logic.
- Search starts from the active trigger query.
- File-list truncation renders the exact daemon-cap warning.
- Empty results render the specified `No matches` state.

## Files changed

Created production files:

- `packages/mobile/lib/feature/chat/logic/attachment_picker.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/suggestion_sheet.dart`
- `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`

Updated production file:

- `packages/mobile/lib/core/helpers/cache/cache_keys.dart`

Created test file:

- `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart`

Updated plan files:

- `docs/superpowers/plans/2026-08-13-flutter-mobile-port-m3.md`
- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-23-brief.md`

Created report:

- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-23-report.md`

## Final verification

Mandated command:

```text
flutter analyze && flutter test
```

Result:

```text
Analyzing mobile...
No issues found! (ran in 2.2s)
00:16 +606: All tests passed!
```

The milestone brief's expected count is stale because Tasks 1–22 and their review corrections grew the suite before Task 23. The verified current total is 606.

No app launch or build command was run, as instructed.

## Self-review

### Clean-code guard

- Read the edited cache file, relevant models and logic, neighboring chat widgets, React Native source, installed package APIs, and repository rules before writing.
- Preserved the brief's explicit public interface and widget/file grouping.
- Added no dependency, local database, networking, generated code, or unrelated refactor.
- Used `CacheHelper` rather than introducing local persistence.
- Added no production comments and no feature-level ScreenUtil usage.
- Used skin colors, `AppTextStyle`, `AppText`, and spacing wrappers.
- Verified `pickMultiImage`, `openFiles`, `XTypeGroup`, `XFile.mimeType`, and file read APIs against installed package versions.
- Caught `AttachmentPickerException` for expected picker failures and `FormatException` for invalid preview encoding; user callback failures remain visible in the composer.
- Added no hardcoded success payloads, disabled tests, dead imports, or speculative configuration.
- `flutter analyze` and `git diff --check` are clean.

### Test guard

- Tests exercise the real stateful composer and real immutable chat models.
- The fake picker replaces only live third-party platform channels.
- Assertions target user-visible controls, field state, callback routing, and attachment payloads rather than internal helper calls.
- No framework guarantees, snapshots, source-text assertions, internal mocks, or duplicate value-only variants were added.
- Each test catches a distinct composer contract regression.

### Mutation check

The focused tests fail for realistic regressions including:

- Sending untrimmed text or failing to clear accepted input
- Invoking send for empty input
- Showing steer outside a running steer-capable turn
- Routing eligible steer text through the new-turn callback
- Removing the running-turn interrupt action
- Dropping images from the send payload or failing to force queue delivery
- Showing embedded text attachment controls without provider capability
- Leaving a stopped controller editable
- Using a non-session-scoped or missing draft cache key

The platform implementation itself is intentionally not invoked by widget tests because both picker packages require live platform channels. Its installed API surface and all restriction branches were reviewed directly; the injected seam keeps production wiring unchanged while allowing deterministic composer behavior coverage.

## Concerns

None blocking. Task 25 is the planned consumer that mounts this composer in the final chat screen; Task 23 intentionally creates the widget and seam without prematurely wiring that later screen composition.

## Review fix round 1

### Findings verified

- A running turn with an empty text field always rendered Stop, even after attachments made the composer non-empty. This made an attachment-only queued message impossible to submit.
- Image and text picker paths allocated the full selected contents before comparing them with their per-file limits.
- The original focused suite did not pin daemon steer refusal, the eight-item total cap, the 25 MB aggregate image cap, or caret-triggered suggestion dismissal.

### Composer RED

Five focused widget regressions were added before changing the composer branch.

Command:

```text
flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart
```

Observed result:

```text
00:00 +6: sends an attachment-only message while a turn is running
Expected: no matching candidates
Actual: Found 1 widget with icon Icons.stop
00:01 +13 -1: Some tests failed.
```

The remaining new regressions were already green during this RED run:

- `steerUnavailable` hid steering and routed text through `onSend`.
- Nine picked attachments retained only the first eight and showed `You can attach up to 8 items.`
- Three 9 MB images retained only the first two and showed `Images must total under 25 MB.`
- Moving the caret into a slash token opened the ranked skill sheet, and dismissing it without another text/caret change did not reopen it.

The minimal fix adds `_attachments.isEmpty` to the running-turn Stop condition. Attachment-only content now renders the queued send control and submits its image payload through `onSend`.

### Composer GREEN

Command:

```text
flutter test test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart
```

Result:

```text
00:01 +14: All tests passed!
```

### Picker preflight RED

The picker restriction tests use a mocked plugin `XFile`, the filesystem/platform boundary, without invoking image or document picker channels. They require an oversized declared length to throw the exact restriction message before the corresponding content read can run.

Command:

```text
flutter test test/feature/chat/logic/attachment_picker_test.dart
```

Observed result:

```text
Error: Method not found: 'imageAttachmentFromFile'.
Error: Method not found: 'textAttachmentFromFile'.
00:00 +0 -1: Some tests failed.
```

The minimal implementation extracts the two file-to-model conversions into platform-independent helpers. Each helper calls `XFile.length()` before `readAsBytes` or `readAsString`, preserves the exact 10 MB and 500 KB restriction messages, and retains a second byte-count check after reading to protect against stale metadata or text encoding differences.

### Picker preflight GREEN

Command:

```text
flutter test test/feature/chat/logic/attachment_picker_test.dart
```

Result:

```text
00:00 +2: All tests passed!
```

### Combined focused GREEN

Command:

```text
flutter test test/feature/chat/logic/attachment_picker_test.dart test/feature/chat/presentation/chat_screen/ui/chat_composer_test.dart
```

Result:

```text
00:01 +16: All tests passed!
```

### Review-fix implementation

- Stop is now shown only when a turn is running, trimmed text is empty, and no attachment is present.
- Attachment-only running-turn submissions remain forced to Queue for next and send their accepted payload.
- Image and text conversions preflight selected-file length before content allocation.
- Post-read image bytes and UTF-8 embedded-text bytes remain checked against the same limits.
- Platform picker wiring still uses only `image_picker` and `file_selector`.
- No app, build, dependency, local persistence, comment, or feature-level ScreenUtil change was introduced.

### Review-fix guard pass

- Widget tests assert rendered controls, exact user errors, accepted payload counts, and callback routing rather than private state.
- The `XFile` mock is limited to the third-party file boundary; `verifyNever` proves oversized files are rejected before the allocation-triggering read.
- Chat models and picked attachments remain real immutable values in widget tests.
- The helpers have current production callers in both platform picker loops and are not speculative exports.
- Installed `XFile.length`, `readAsBytes`, and `readAsString` APIs were verified against `cross_file` 0.3.5+4.
- `flutter analyze` and `git diff --check` are clean.

### Review-fix final verification

Mandated command:

```text
flutter analyze && flutter test
```

Result:

```text
Analyzing mobile...
No issues found! (ran in 1.9s)
00:20 +613: All tests passed!
```

Review fix round 1 adds seven focused tests to the prior 606-test suite. No app launch or build command was run.

### Review-fix concerns

None blocking.
