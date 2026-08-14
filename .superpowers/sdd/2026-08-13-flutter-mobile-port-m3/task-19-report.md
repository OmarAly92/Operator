# Task 19 report

## Scope

Extended `ChatCubit` with the daemon-wide conversation event stream. The cubit now accepts `ServerConfigStore`, starts the stream only after an authoritative conversation page is available, persists its per-server/session cursor, filters daemon-wide events to the active session and conversation, debounces refreshes, reconnects with the specified bounded backoff, reloads on foreground resume, and tears down stream resources on close.

The service locator supplies `ServerConfigStore`. Existing ChatCubit tests now initialise the cache, provide a server configuration, and keep a live event stream available.

## TDD evidence

1. Added `chat_cubit_stream_test.dart` before the production implementation.
2. Ran `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart` before implementation. It failed because `ChatCubit` had no `configStore` parameter and no `onResumed` method. The test fixture also required removal of invalid `const Result.success` expressions and registration of a Mocktail `CancelToken` fallback so the intended contract failure could compile cleanly.
3. Added the minimal constructor, stream lifecycle, cursor, debounce, backoff, service-locator, and test-fixture changes.
4. Re-ran `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`: 7 passing tests.
5. Ran `flutter test test/feature/chat/presentation/chat_screen/logic/`: 43 passing tests.

## Test review

Reviewed the new test file against the repository testing conventions. Each test covers a separate externally observable stream behavior: refresh coalescing, event filtering, durable cursor persistence and reuse, reconnect, foreground refresh, and permanent-unavailability suppression. Repository and configuration mocks remain at the network/configuration boundary; event and snapshot values use real models.

## Final verification

From `packages/mobile`:

- `flutter analyze` completed with `No issues found!`.
- `flutter test` completed successfully with 556 passing tests.

## Review fix round 1

### Files changed

- `packages/mobile/lib/feature/chat/presentation/chat_screen/logic/chat_cubit.dart`
- `packages/mobile/test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`
- `.superpowers/sdd/2026-08-13-flutter-mobile-port-m3/task-19-report.md`

### RED

Added `stops an active stream when the conversation becomes permanently unavailable`. The test opens a stream from a successful initial page, refreshes to a `SESSION_NOT_FOUND` failure, then drops the old stream. It requires exactly one `repository.events` call.

Command:

`flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart`

Output before the production change: failed at the new test with `Expected: <1> Actual: <2>`, proving the dropped active stream scheduled a reconnect after permanent unavailability.

### GREEN

Added `_stopEvents()` and invoke it when a permanent conversation failure is applied. It disables streaming, cancels and clears the refresh/reconnect timers and cancel token, cancels and clears the subscription, and is shared by `close()`.

Commands and outputs:

- `flutter test test/feature/chat/presentation/chat_screen/logic/chat_cubit_stream_test.dart` — 8 passing tests.
- `flutter test test/feature/chat/presentation/chat_screen/logic/` — 44 passing tests.
- `flutter analyze` — `No issues found!`.
- `flutter test` — 557 passing tests.
