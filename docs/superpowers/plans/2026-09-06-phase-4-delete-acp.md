# Phase 4 — Delete ACP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the ACP/Chat subsystem from all three deliverables — backend, desktop renderer, and mobile — leaving the TUI-plus-blocks architecture as the only path, with no dangling references and no dead schema.

**Architecture:** This is a deletion, executed leaf-first so the tree builds and the suite passes at every commit. Callers are severed before callees: mobile and desktop stop referencing chat, then the HTTP routes go, then the service, then the adapters, then the domain and ports vocabulary, and the schema drops last. Three seams inside mobile carry live, non-chat functionality and must be extracted before anything is deleted; everything else is removal.

**Tech Stack:** Go 1.x (chi, sqlc, goose, code-first OpenAPI via `specgen`), Flutter 3.44.5 (cubit-only), React + Vite + Tauri.

**Spec:** [`docs/superpowers/specs/2026-09-04-single-session-interface-design.md`](../specs/2026-09-04-single-session-interface-design.md), "Phase 4 — delete ACP" (line 601).

## Global Constraints

- **No comments.** The user's global instruction. Do not add explanatory comments to code you touch. Deleting a commented block deletes its comments with it; that is expected.
- **`golangci-lint` reports phantom issues from stale cache.** Nested worktrees under `.worktrees/` and `.claude/worktrees/` leave deleted paths in the lint cache. If `golangci-lint run ./...` reports an issue in a path that does not exist, run `golangci-lint cache clean` and re-run. Only the post-clean result counts.
- **Repo-wide `grep` and `find` from the root are unreliable.** `.worktrees/`, `.claude/worktrees/` and sibling `../Operator-*` checkouts hold stale duplicates of tracked files. Scope every search to `backend/`, `frontend/src/`, `packages/mobile/lib/`, `packages/mobile/test/`, or exclude those two paths explicitly.
- **`flutter analyze` must print exactly `No issues found!`** — warnings are failures. Run from `packages/mobile`.
- **Route changes require regenerating the API contract.** `npm run api` (runs `api:spec` then `api:ts`). A route deleted without regenerating fails the `api-drift` CI job and the spec-parity tests in `backend/internal/httpd/...`.
- **Use the repo's own script wrappers, not the raw tools.** `npm run lint` from the root is backend `go test ./...` plus `golangci-lint` v2.12.2; `npm run sqlc` regenerates `backend/internal/storage/sqlite/gen`; `npm run api` regenerates the spec and TS types; `npm run typecheck`, `npm run lint` and `npm test` are the frontend gates, run from `frontend/`. `frontend` has no `build` script — do not invent one.
- **Every task ends green.** The gate for a deletion task is: the full suite passes, and no symbol from the deleted set is still referenced. There is no red-green cycle to run — the inverted TDD step is "grep proves zero references, then the suite proves nothing broke".
- **Do not refactor while deleting.** No renames, no reformatting, no "while I'm here" improvements. A deletion diff that also moves code is unreviewable.

## What the spec got right, and what has changed since

The spec's non-test line counts are still exact: `chatdriver/` is 12,574 non-test lines across 27 files (18,642 including tests, 48 files), `service/chat/` is 3,879 non-test lines across 5 files (8,222 including tests, 11 files), and `interface_transition.go` is 1,073 lines. The `ConversationsController` registers exactly the eighteen routes the spec names.

Four things the spec does not say, all discovered by reading the tree on 2026-09-06:

1. **Phase 3 is merged** (`8bff2c80c`), so the trigger the spec names has fired.
2. **The API already rejects `sessionMode`.** `controllers/sessions.go:257` has `sessionModeRequested` and `writeSessionModeRemoved`, wired into three handlers. Phase 1 closed the public surface; only internals and the column remain.
3. **Three seams inside `packages/mobile/lib/feature/chat/` carry live functionality** used by the terminal and blocks screens: the entire `voice/` dictation subsystem (7 files, 862 lines) imported by `terminal_composer.dart`, `logic/keyboard_inset.dart` (6 lines) imported by `terminal_body.dart`, and the conversation-typed halves of two `blocks/logic/` files. These are Tasks 1–3 and must land before any deletion.
4. **The live blocks stack is already clean.** `blocks_cubit.dart`, `blocks_body.dart`, and every block widget (`block_list`, `block_card`, `block_selection_bar`, `block_action_sheet`, `turn_group_status`) reference **zero** conversation-typed symbols. The chat-side blocks files (`conversation_blocks_cubit`, `conversation_blocks_state`, `chat_blocks_body`, `blocks/logic/conversation_blocks.dart`) are reachable only from `chat_body.dart` and go with chat.
5. **`SessionBlocksPane` and `ChatSessionBlocksPane` in `CenterPane.tsx` have no callers.** The desktop chat surface is already orphaned; only the `i18n/renderer-coverage.test.ts` registry still names `components/chat`.

## File Structure

**Extracted before deletion (mobile):**
- Create `packages/mobile/lib/feature/dictation/` — the voice subsystem's new home, moved verbatim from `feature/chat/voice/`.
- Create `packages/mobile/lib/core/utils/keyboard_inset.dart` — 6 lines moved from `feature/chat/logic/`.
- Modify `packages/mobile/lib/feature/blocks/logic/block_actions.dart` and `turn_grouping.dart` — drop their conversation-typed halves.

**Deleted (mobile):** `lib/feature/chat/` (all remaining), `lib/core/events/conversation_event_bus.dart`, four chat-side files under `lib/feature/blocks/`, the 16 conversation entries in `core/api/api_request_helpers/end_points.dart`, and 26 test files under `test/feature/chat/` plus the chat-side blocks tests.

**Deleted (desktop):** `frontend/src/renderer/components/chat/` (19 files), `SessionBlocksPane`/`ChatSessionBlocksPane` in `CenterPane.tsx`, `hooks/useConversation.ts`, `lib/conversation-blocks.ts`, `lib/chat-fixture.ts`, `types/conversation.ts`, and the conversation branches of `lib/event-transport.ts` and `components/blocks/BlockComposer.tsx`.

**Deleted (backend), in dependency order:** the nine `controllers/conversation*` files → `service/chat/` → `adapters/chatdriver/` and `cmd/gencodexproto` → `session_manager/{interface_transition,chat_spawn,chat_attachments}.go` → `ports/chat.go`, `domain/{conversation,session_interface_transition,sessionmode}.go` → sqlc queries, generated code, and stores → migration 0101.

**Deleted (build):** `frontend/acp-runtime/`, `frontend/scripts/build-acp-runtime.mjs`, the `build:acp-runtime` script in both `package.json` files, the resource entry in `tauri.conf.json`, the two references in `verify-tauri-artifacts.sh`, and the `npm run build:acp-runtime` step in six CI workflows.

---

### Task 1: Extract the dictation subsystem out of `feature/chat`

Dictation is live: `terminal_composer.dart` uses `VoiceInputCubit`, `MicKey` and `VoiceStrip` to drive the vendored `speech_to_text` fork. It lives under `feature/chat/voice/` only because chat was built first. It moves to its own feature so chat can be deleted.

**Files:**
- Create: `packages/mobile/lib/feature/dictation/` — `device_provider.dart`, `speech_recognizer.dart`, `voice_types.dart`, `logic/voice_input_cubit.dart`, `logic/voice_input_state.dart`, `ui/mic_key.dart`, `ui/voice_strip.dart`
- Delete: `packages/mobile/lib/feature/chat/voice/` (the same 7 files)
- Modify: `packages/mobile/lib/core/utils/service_locator.dart:15-18`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart:11-13`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart` (and any other in-chat importer — find them in Step 2)
- Move: `packages/mobile/test/feature/chat/voice/device_provider_test.dart` → `packages/mobile/test/feature/dictation/device_provider_test.dart`
- Move: `packages/mobile/test/feature/chat/voice/mic_key_test.dart` → `packages/mobile/test/feature/dictation/mic_key_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart` exporting `VoiceInputCubit` and `VoiceInputState`; `.../feature/dictation/ui/mic_key.dart` exporting `MicKey`; `.../feature/dictation/ui/voice_strip.dart` exporting `VoiceStrip`; `.../feature/dictation/device_provider.dart`, `.../speech_recognizer.dart`, `.../voice_types.dart`. Class names and signatures are unchanged — this is a move, not a rewrite. Task 4 relies on `feature/chat/voice/` no longer existing.

- [ ] **Step 1: Record the current test count as the baseline**

```bash
cd packages/mobile && flutter test 2>&1 | tail -3
```

Write the number down. Every later task compares against it: a move must not change it, a deletion must only subtract the tests it deletes.

- [ ] **Step 2: Find every importer of the voice subsystem**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "feature/chat/voice" packages/mobile/lib packages/mobile/test | sort
```

Expected: `service_locator.dart` (5 imports), `terminal_composer.dart` (3), the two voice tests, and any importer inside `feature/chat/` itself. The in-chat importers are fixed here too so the tree stays green; they are deleted in Task 4.

- [ ] **Step 3: Move the files with `git mv`, preserving history**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
mkdir -p lib/feature/dictation/logic lib/feature/dictation/ui test/feature/dictation
git mv lib/feature/chat/voice/device_provider.dart      lib/feature/dictation/device_provider.dart
git mv lib/feature/chat/voice/speech_recognizer.dart    lib/feature/dictation/speech_recognizer.dart
git mv lib/feature/chat/voice/voice_types.dart          lib/feature/dictation/voice_types.dart
git mv lib/feature/chat/voice/logic/voice_input_cubit.dart lib/feature/dictation/logic/voice_input_cubit.dart
git mv lib/feature/chat/voice/logic/voice_input_state.dart lib/feature/dictation/logic/voice_input_state.dart
git mv lib/feature/chat/voice/ui/mic_key.dart           lib/feature/dictation/ui/mic_key.dart
git mv lib/feature/chat/voice/ui/voice_strip.dart       lib/feature/dictation/ui/voice_strip.dart
git mv test/feature/chat/voice/device_provider_test.dart test/feature/dictation/device_provider_test.dart
git mv test/feature/chat/voice/mic_key_test.dart         test/feature/dictation/mic_key_test.dart
rmdir lib/feature/chat/voice/logic lib/feature/chat/voice/ui lib/feature/chat/voice test/feature/chat/voice 2>/dev/null || true
```

- [ ] **Step 4: Rewrite every import path**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
grep -rl "feature/chat/voice/" lib test | while read -r f; do
  perl -pi -e 's{feature/chat/voice/logic/}{feature/dictation/logic/}g;
               s{feature/chat/voice/ui/}{feature/dictation/ui/}g;
               s{feature/chat/voice/}{feature/dictation/}g' "$f"
done
grep -rn "feature/chat/voice" lib test | sort
```

Expected from the final grep: no output.

- [ ] **Step 5: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
flutter analyze
flutter test 2>&1 | tail -3
```

Expected: `No issues found!`, and the same test count as Step 1. A move changes no behaviour, so any delta is a mistake.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A packages/mobile
git commit -m "$(cat <<'MSG'
refactor(mobile): move dictation out of the chat feature

Dictation drives the terminal composer and outlives chat. It lived under
feature/chat/voice only because chat was built first.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: Move `keyboardInset` into core

Six lines that `terminal_body.dart` depends on. It is a pure layout helper with no chat concepts in it.

**Files:**
- Create: `packages/mobile/lib/core/utils/keyboard_inset.dart`
- Delete: `packages/mobile/lib/feature/chat/logic/keyboard_inset.dart`
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart:11`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart`
- Move: `packages/mobile/test/feature/chat/logic/keyboard_inset_test.dart` → `packages/mobile/test/core/utils/keyboard_inset_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `package:operator_mobile/core/utils/keyboard_inset.dart`, exporting the same symbol under the same name. Task 4 relies on `feature/chat/logic/keyboard_inset.dart` being gone.

- [ ] **Step 1: Read the file so the move is verifiably verbatim**

```bash
cat packages/mobile/lib/feature/chat/logic/keyboard_inset.dart
```

- [ ] **Step 2: Move it**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
git mv lib/feature/chat/logic/keyboard_inset.dart lib/core/utils/keyboard_inset.dart
git mv test/feature/chat/logic/keyboard_inset_test.dart test/core/utils/keyboard_inset_test.dart
grep -rl "feature/chat/logic/keyboard_inset.dart" lib test | while read -r f; do
  perl -pi -e 's{feature/chat/logic/keyboard_inset\.dart}{core/utils/keyboard_inset.dart}g' "$f"
done
grep -rn "chat/logic/keyboard_inset" lib test
```

Expected from the final grep: no output.

- [ ] **Step 3: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
flutter analyze && flutter test 2>&1 | tail -3
```

Expected: `No issues found!` and the Task 1 baseline count.

- [ ] **Step 4: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A packages/mobile
git commit -m "$(cat <<'MSG'
refactor(mobile): move keyboardInset into core utils

The terminal body uses it; it carries no chat concepts.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: Split the conversation halves out of two blocks-logic files

`blocks/logic/block_actions.dart` and `blocks/logic/turn_grouping.dart` are each used by live block widgets *and* by chat-side code, and each imports chat models for the chat half only. The live widgets (`block_list`, `block_card`, `blocks_body`, `block_selection_bar`, `block_action_sheet`, `turn_group_status`) reference zero conversation-typed symbols — verified by grep on 2026-09-06 — so the chat half can be cut cleanly.

**Files:**
- Modify: `packages/mobile/lib/feature/blocks/logic/block_actions.dart` — delete the declarations that mention `ConversationSnapshotModel` or `ConversationTurnModel`, and the two imports at lines 3-4
- Modify: `packages/mobile/lib/feature/blocks/logic/turn_grouping.dart` — delete the declarations that mention `ConversationActivityModel`, `ConversationByTurn`, `ConversationGroup`, `ConversationItemModel`, `ConversationItems`, `ConversationSnapshotModel` or `ConversationTurnModel`, and the three imports at lines 2-4
- Delete: `packages/mobile/test/feature/blocks/logic/block_assembly_fixtures_test.dart` (chat-fixture driven), and the conversation-typed test groups inside `test/feature/blocks/logic/turn_grouping_transcript_test.dart` and `turn_grouping_fixtures_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `block_actions.dart` and `turn_grouping.dart` with no `feature/chat` imports. Task 4 relies on this: with these two files clean, no file outside `feature/chat/` and the four chat-side blocks files imports chat.

- [ ] **Step 1: Enumerate what the live widgets actually use from each file**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
for w in block_list block_card blocks_body block_selection_bar block_action_sheet turn_group_status; do
  echo "--- $w"
  grep -oE "\b(groupTurns|blockActionsFor|[a-zA-Z]+Turn[A-Za-z]*|[a-zA-Z]*Action[A-Za-z]*|[a-zA-Z]*Group[A-Za-z]*)\b" \
    lib/feature/blocks/presentation/blocks_screen/ui/widgets/$w.dart | sort -u | tr '\n' ' '; echo
done
```

Everything printed must survive. Everything in the two logic files that is *not* printed and *is* conversation-typed is removed.

- [ ] **Step 2: Confirm the live widgets touch no conversation types**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
grep -rn "Conversation" lib/feature/blocks/presentation/blocks_screen/ui/widgets/*.dart \
  | grep -v chat_blocks_body
```

Expected: no output. If this prints anything, stop — the seam is not where this plan says it is, and the split needs redesigning before proceeding.

- [ ] **Step 3: Delete the conversation-typed declarations and their imports**

Remove from each file every top-level function, class, extension and typedef whose signature or body names one of the conversation types listed under **Files**, then delete the now-unused `package:operator_mobile/feature/chat/...` imports at the top. Leave every other declaration byte-for-byte unchanged.

- [ ] **Step 4: Prove the chat imports are gone**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
grep -rn "feature/chat" lib/feature/blocks/logic/
```

Expected: no output.

- [ ] **Step 5: Remove the tests that covered the deleted halves**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
git rm test/feature/blocks/logic/block_assembly_fixtures_test.dart
flutter analyze
```

`flutter analyze` names every remaining test that references a deleted symbol. Delete exactly those `group(...)`/`test(...)` blocks from `turn_grouping_transcript_test.dart` and `turn_grouping_fixtures_test.dart`, leaving the transcript-driven cases — those cover the live path — intact.

- [ ] **Step 6: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
flutter analyze && flutter test 2>&1 | tail -3
```

Expected: `No issues found!`, and a test count *below* the Task 1 baseline by exactly the number of deleted cases. Record the new baseline.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A packages/mobile
git commit -m "$(cat <<'MSG'
refactor(mobile): drop the conversation halves of the blocks logic

block_actions and turn_grouping served both the live blocks view and the
chat timeline. Only the live half has callers.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: Delete the mobile chat feature

With Tasks 1–3 landed, nothing outside `feature/chat/` and its four chat-side satellites imports chat.

**Files:**
- Delete: `packages/mobile/lib/feature/chat/` (everything remaining)
- Delete: `packages/mobile/lib/core/events/conversation_event_bus.dart`
- Delete: `packages/mobile/lib/feature/blocks/logic/conversation_blocks.dart`
- Delete: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart`
- Delete: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart`
- Delete: `packages/mobile/lib/feature/blocks/presentation/blocks_screen/ui/widgets/chat_blocks_body.dart`
- Delete: `packages/mobile/test/feature/chat/` (26 files), `test/core/events/conversation_event_bus_test.dart`, `test/feature/blocks/logic/conversation_blocks_test.dart`, `test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart`, `test/feature/blocks/presentation/chat_blocks_body_test.dart`, `test/feature/blocks/presentation/conversation_blocks_cubit_test.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart` — remove the chat registrations
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart:25-44` — remove the 16 conversation endpoint methods
- Modify: `packages/mobile/lib/core/routing/` — remove the chat route name and its case (find it in Step 2)
- Modify: `packages/mobile/test/core/utils/service_locator_test.dart`, `test/core/utils/haptics_call_sites_test.dart`

**Interfaces:**
- Consumes: `feature/dictation/*` and `core/utils/keyboard_inset.dart` from Tasks 1–2; clean `blocks/logic/*` from Task 3.
- Produces: a mobile tree with no `feature/chat`, no `/conversation` endpoint strings, and no `ConversationEventBus`. Task 6 relies on mobile having stopped calling the eighteen routes.

- [ ] **Step 1: Snapshot the deletion set**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
find lib/feature/chat test/feature/chat -type f | wc -l
grep -rn "RoutesStrings" lib/core/routing/*.dart | grep -i chat
```

- [ ] **Step 2: Delete the files**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
git rm -r lib/feature/chat test/feature/chat
git rm lib/core/events/conversation_event_bus.dart test/core/events/conversation_event_bus_test.dart
git rm lib/feature/blocks/logic/conversation_blocks.dart
git rm lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart
git rm lib/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_state.dart
git rm lib/feature/blocks/presentation/blocks_screen/ui/widgets/chat_blocks_body.dart
git rm test/feature/blocks/logic/conversation_blocks_test.dart
git rm test/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit_stream_test.dart
git rm test/feature/blocks/presentation/chat_blocks_body_test.dart
git rm test/feature/blocks/presentation/conversation_blocks_cubit_test.dart
```

- [ ] **Step 3: Let the analyzer drive the cleanup**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
flutter analyze 2>&1 | head -60
```

Every reported error is a dangling reference in `service_locator.dart`, the routing table, or a test. Fix them by deletion, not by stubbing. Repeat until clean.

- [ ] **Step 4: Remove the conversation endpoints**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
grep -n "conversation" lib/core/api/api_request_helpers/end_points.dart
```

Delete each of the 16 methods the grep prints, then confirm:

```bash
grep -rn "conversation" lib/core/api/ && echo "STILL PRESENT" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 5: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/packages/mobile
flutter analyze && flutter test 2>&1 | tail -3
grep -rn "feature/chat\|ConversationEventBus\|/conversation" lib | sort
```

Expected: `No issues found!`, a green suite, and no output from the grep.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A packages/mobile
git commit -m "$(cat <<'MSG'
feat(mobile)!: remove the chat feature

BREAKING CHANGE: the phone no longer has a chat screen. Sessions are the
terminal and the blocks view over the TUI.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: Delete the desktop chat surface

`SessionBlocksPane` and `ChatSessionBlocksPane` in `CenterPane.tsx` have no callers, and only the i18n coverage registry still names `components/chat`.

**Files:**
- Delete: `frontend/src/renderer/components/chat/` (19 files)
- Delete: `frontend/src/renderer/hooks/useConversation.ts`, `useConversation.test.tsx`
- Delete: `frontend/src/renderer/lib/conversation-blocks.ts`, `conversation-blocks.test.ts`, `chat-fixture.ts`
- Delete: `frontend/src/renderer/types/conversation.ts`
- Modify: `frontend/src/renderer/components/CenterPane.tsx` — remove `SessionBlocksPane`, `ChatSessionBlocksPane`, and the `useConversation*` imports at lines 36-43
- Modify: `frontend/src/renderer/i18n/renderer-coverage.test.ts` — drop the `components/chat` entries
- Modify: `frontend/src/renderer/lib/event-transport.ts`, `frontend/src/renderer/components/blocks/BlockComposer.tsx`, `frontend/src/renderer/hooks/useRestoreSession.ts`, `frontend/src/renderer/types/capabilities.test.ts`, `frontend/src/renderer/components/SessionsBoard.test.tsx` — remove conversation branches

**Interfaces:**
- Consumes: nothing.
- Produces: a renderer with no conversation types. Task 6 regenerates `frontend/src/api/schema.ts`, which still contains conversation schemas until then — that is expected and is fixed there, not here.

- [ ] **Step 1: Confirm the panes are unreachable**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "SessionBlocksPane" frontend/src --include='*.tsx' --include='*.ts' | grep -v "CenterPane.tsx"
```

Expected: no output. If this prints a caller, stop and report — the desktop surface is live and this task needs redesigning.

- [ ] **Step 2: Delete the files**

```bash
cd /Users/omaraly/development/AI/Operator
git rm -r frontend/src/renderer/components/chat
git rm frontend/src/renderer/hooks/useConversation.ts frontend/src/renderer/hooks/useConversation.test.tsx
git rm frontend/src/renderer/lib/conversation-blocks.ts frontend/src/renderer/lib/conversation-blocks.test.ts
git rm frontend/src/renderer/lib/chat-fixture.ts
git rm frontend/src/renderer/types/conversation.ts
```

- [ ] **Step 3: Let the type checker drive the cleanup**

```bash
cd /Users/omaraly/development/AI/Operator/frontend && npm run typecheck 2>&1 | head -40
```

Fix each error by deleting the dangling code. In `CenterPane.tsx` that means removing both pane functions and the five `useConversation*` imports; in `event-transport.ts` and `BlockComposer.tsx` it means removing the conversation branches, not stubbing them.

- [ ] **Step 4: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/frontend
npm run typecheck && npm run lint && npm test 2>&1 | tail -5
grep -rn "components/chat\|useConversation\|conversation-blocks" src | sort
```

Expected: clean type check, clean lint, green tests, and no output from the grep other than `src/api/schema.ts` (regenerated in Task 6).

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A frontend/src
git commit -m "$(cat <<'MSG'
feat(desktop)!: remove the chat renderer surface

BREAKING CHANGE: the desktop app is the terminal. The chat pane had no
callers after phase 1.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Delete the eighteen `/conversation` routes and regenerate the API contract

**Files:**
- Delete: `backend/internal/httpd/controllers/conversations.go`, `conversations_skills.go`, `conversation_steer.go`, and the six matching `*_test.go` files
- Modify: `backend/internal/httpd/api.go:53-55, 87, 123, 159` — remove the `Conversations` dep, the controller field, its construction and its `Register` call
- Modify: `backend/internal/httpd/controllers/dto.go:1329-1400` — remove the chat conversation DTO block
- Modify: `backend/internal/httpd/apispec/specgen/build.go` — remove the conversation operations and their `schemaNames` entries
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Consumes: mobile (Task 4) and desktop (Task 5) no longer call these routes.
- Produces: an `APIDeps` with no `Conversations` field. Task 7 removes the wiring in `daemon.go` that used to populate it.

- [ ] **Step 1: Record the route list being removed**

```bash
cd /Users/omaraly/development/AI/Operator
sed -n '62,80p' backend/internal/httpd/controllers/conversations.go
```

Eighteen registrations. All eighteen go.

- [ ] **Step 2: Delete the controller files**

```bash
cd /Users/omaraly/development/AI/Operator
git rm backend/internal/httpd/controllers/conversations.go \
       backend/internal/httpd/controllers/conversations_skills.go \
       backend/internal/httpd/controllers/conversation_steer.go \
       backend/internal/httpd/controllers/conversations_test.go \
       backend/internal/httpd/controllers/conversations_skills_test.go \
       backend/internal/httpd/controllers/conversations_config_options_test.go \
       backend/internal/httpd/controllers/conversation_steer_test.go \
       backend/internal/httpd/controllers/conversation_history_test.go \
       backend/internal/httpd/controllers/conversation_provider_state_test.go
```

- [ ] **Step 3: Unwire the controller and remove the DTOs**

Remove the `Conversations` field and its comment from `APIDeps`, the `conversations` field from the API struct, its construction, and the `a.conversations.Register(r)` call. Then delete the `/* ---- chat conversations ---- */` block from `dto.go`.

- [ ] **Step 4: Let the compiler find the rest**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go build ./... 2>&1 | head -30
```

Fix each error by deletion. `service/chat` is still present at this point and still compiles; only its HTTP callers are gone.

- [ ] **Step 5: Remove the operations from the spec registry and regenerate**

```bash
cd /Users/omaraly/development/AI/Operator
grep -n -i conversation backend/internal/httpd/apispec/specgen/build.go | head -40
```

Delete every printed entry, then:

```bash
npm run api
grep -c conversation backend/internal/httpd/apispec/openapi.yaml
```

Expected from the final grep: `0`.

- [ ] **Step 6: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go test ./internal/httpd/... 2>&1 | tail -20
```

Expected: no gofmt output, clean vet, and green route/spec parity tests. Then confirm the generated TS is clean:

```bash
cd /Users/omaraly/development/AI/Operator && grep -c conversation frontend/src/api/schema.ts
```

Expected: `0`.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend frontend/src/api
git commit -m "$(cat <<'MSG'
feat(api)!: remove the eighteen conversation routes

BREAKING CHANGE: /api/v1/sessions/{sessionId}/conversation and every route
below it is gone, along with its OpenAPI operations and generated types.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: Delete the chat service and its daemon wiring

**Files:**
- Delete: `backend/internal/service/chat/` (11 files, 8,222 lines)
- Modify: `backend/internal/daemon/daemon.go` — remove the chat service construction and the `Conversations` dep it fed
- Modify: `backend/internal/daemon/lifecycle_wiring.go` — remove the chat controller wiring and the interface-transition manager wiring

**Interfaces:**
- Consumes: the `APIDeps.Conversations` field is already gone (Task 6).
- Produces: a daemon that constructs no chat service. Task 8 deletes the drivers it used to hold.

- [ ] **Step 1: Confirm the only remaining importers are the two daemon files**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rln "internal/service/chat" backend --include='*.go' | grep -v "internal/service/chat/" | sort
```

Expected: exactly `backend/internal/daemon/daemon.go` and `backend/internal/daemon/lifecycle_wiring.go`. Anything else means Task 6 left a caller behind — fix that first.

- [ ] **Step 2: Delete the package**

```bash
cd /Users/omaraly/development/AI/Operator && git rm -r backend/internal/service/chat
```

- [ ] **Step 3: Unwire the daemon**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go build ./... 2>&1 | head -30
```

Remove each reported reference from `daemon.go` and `lifecycle_wiring.go` by deletion. The `chatdriver` registry construction stays for now — it is deleted in Task 8 — but anything that only existed to hand drivers to the chat service goes here.

- [ ] **Step 4: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go test ./... 2>&1 | grep -E "^(FAIL|ok +github.com/OmarAly92/operator/backend/internal/daemon)" | head
```

Expected: no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend
git commit -m "$(cat <<'MSG'
feat(backend)!: remove the chat service

BREAKING CHANGE: the daemon no longer runs a conversation controller.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8: Delete the ACP driver stack

**Files:**
- Delete: `backend/internal/adapters/chatdriver/` (48 files, 18,642 lines)
- Delete: `backend/cmd/gencodexproto/`
- Modify: `backend/internal/daemon/daemon.go` — remove the `registry.Build(log)` call and its import

**Interfaces:**
- Consumes: nothing constructs a driver after Task 7 except `daemon.go`.
- Produces: no package imports `acp-go-sdk`. Task 9 removes the runtime resource the Claude driver used to resolve.

- [ ] **Step 1: Confirm the importer set**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rln "adapters/chatdriver" backend --include='*.go' | grep -v "internal/adapters/chatdriver/" | sort
```

Expected: exactly `backend/cmd/gencodexproto/main.go` and `backend/internal/daemon/daemon.go`.

- [ ] **Step 2: Delete**

```bash
cd /Users/omaraly/development/AI/Operator
git rm -r backend/internal/adapters/chatdriver backend/cmd/gencodexproto
```

- [ ] **Step 3: Unwire and drop the dependency**

```bash
cd /Users/omaraly/development/AI/Operator/backend
go build ./... 2>&1 | head -20
```

Remove the reported references from `daemon.go`, then:

```bash
cd /Users/omaraly/development/AI/Operator/backend && go mod tidy && git diff --stat go.mod go.sum
```

Expected: `github.com/coder/acp-go-sdk` dropped from `go.mod`.

- [ ] **Step 4: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go build ./... && go test ./... 2>&1 | grep -c "^FAIL"
```

Expected: `0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend
git commit -m "$(cat <<'MSG'
feat(backend)!: remove the ACP driver stack

BREAKING CHANGE: claudeacp, opencodeacp, droidacp, the codex app-server
driver and the shared ACP transport are gone, along with the acp-go-sdk
dependency.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 9: Remove the ACP runtime from the build and release pipelines

The runtime is a bundled npm package resolved by the deleted Claude driver. It is referenced by two `package.json` files, the Tauri resource map, the artifact verifier, and six CI workflows — every one of which will now fail on a missing script.

**Files:**
- Delete: `frontend/acp-runtime/`, `frontend/scripts/build-acp-runtime.mjs`
- Modify: `package.json:5`, `frontend/package.json:15`
- Modify: `frontend/src-tauri/tauri.conf.json:27`
- Modify: `frontend/scripts/verify-tauri-artifacts.sh:340, 679`
- Modify: `.github/workflows/tauri-webdriver.yml:90`, `frontend-release.yml:86,269`, `feature-release.yml:271,430`, `build-artifacts.yml:97`, `testing-build.yml:65`

**Interfaces:**
- Consumes: the driver that resolved `resources/acp-runtime` is gone (Task 8).
- Produces: no build step named `build:acp-runtime`. Nothing depends on this task.

- [ ] **Step 1: Enumerate every reference**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "acp-runtime" --include='*.json' --include='*.mjs' --include='*.sh' --include='*.yml' \
  package.json frontend .github | grep -v node_modules
```

- [ ] **Step 2: Delete the package and its build script**

```bash
cd /Users/omaraly/development/AI/Operator
git rm -r frontend/acp-runtime frontend/scripts/build-acp-runtime.mjs
```

- [ ] **Step 3: Remove the script entries, the resource, the verifier lines and the CI steps**

Delete the `"build:acp-runtime"` line from both `package.json` files, the `"../resources/acp-runtime/": "acp-runtime/"` entry from `tauri.conf.json`, `acp-runtime` from both resource lists in `verify-tauri-artifacts.sh`, and the `npm run build:acp-runtime` step (with its `- run:` / `run:` wrapper) from all six workflows.

- [ ] **Step 4: Verify nothing references it**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "acp-runtime\|acp_runtime" --include='*.json' --include='*.mjs' --include='*.sh' --include='*.yml' --include='*.go' \
  package.json frontend backend .github | grep -v node_modules | grep -v package-lock
```

Expected: no output.

- [ ] **Step 5: Confirm the JSON is still valid and the app still builds**

```bash
cd /Users/omaraly/development/AI/Operator
node -e "JSON.parse(require('fs').readFileSync('package.json'));JSON.parse(require('fs').readFileSync('frontend/package.json'));JSON.parse(require('fs').readFileSync('frontend/src-tauri/tauri.conf.json'));console.log('json ok')"
cd frontend && npm run typecheck 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A package.json frontend .github
git commit -m "$(cat <<'MSG'
build!: drop the ACP runtime resource and its pipeline

BREAKING CHANGE: build:acp-runtime is removed from both package manifests,
the Tauri resource map, the artifact verifier and six workflows.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 10: Delete the interface-transition saga and chat spawn

**Files:**
- Delete: `backend/internal/session_manager/interface_transition.go`, `interface_transition_test.go`, `chat_spawn.go`, `chat_spawn_test.go`, `chat_attachments.go`
- Modify: `backend/internal/session_manager/manager.go`, `manager_test.go` — remove the transition and chat-spawn entry points
- Modify: `backend/internal/daemon/lifecycle_wiring.go` — remove the transition manager wiring
- Modify: `backend/internal/service/session/service.go` — remove the transition calls
- Delete: `backend/internal/storage/sqlite/store/session_interface_transition_store.go` and its test
- Delete: `backend/internal/domain/session_interface_transition.go`

**Interfaces:**
- Consumes: no chat service remains to drive a transition (Task 7).
- Produces: a session manager that only spawns TUI sessions. Task 11 removes `SessionMode` itself, which this task's deletions make unreferenced in the manager.

- [ ] **Step 1: Map the references before cutting**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "InterfaceTransition" backend/internal/session_manager/manager.go \
  backend/internal/service/session/service.go backend/internal/daemon/lifecycle_wiring.go
grep -rn "chatSpawn\|ChatSpawn\|chatAttachments" backend/internal/session_manager/manager.go
```

- [ ] **Step 2: Delete the files**

```bash
cd /Users/omaraly/development/AI/Operator
git rm backend/internal/session_manager/interface_transition.go \
       backend/internal/session_manager/interface_transition_test.go \
       backend/internal/session_manager/chat_spawn.go \
       backend/internal/session_manager/chat_spawn_test.go \
       backend/internal/session_manager/chat_attachments.go \
       backend/internal/storage/sqlite/store/session_interface_transition_store.go \
       backend/internal/storage/sqlite/store/session_interface_transition_store_test.go \
       backend/internal/domain/session_interface_transition.go
```

- [ ] **Step 3: Let the compiler drive**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go build ./... && go vet ./... 2>&1 | head -30
```

Delete each dangling reference. In `manager.go` this removes the mode branch from session creation; in `service/session/service.go` it removes the transition calls. Do not leave a mode parameter that is now always `tui` — remove the parameter.

- [ ] **Step 4: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go test ./... 2>&1 | grep -c "^FAIL"
```

Expected: `0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend
git commit -m "$(cat <<'MSG'
feat(backend)!: remove the interface-transition saga and chat spawn

BREAKING CHANGE: a session cannot change interface mode, because there is
only one mode.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 11: Delete the chat vocabulary from ports and domain

**Files:**
- Delete: `backend/internal/ports/chat.go` (840 lines)
- Delete: `backend/internal/domain/conversation.go`, `backend/internal/domain/sessionmode.go`, `sessionmode_test.go`
- Delete: `backend/internal/storage/sqlite/store/conversation_store.go`, `conversation_branch_store_test.go`, `conversation_history_store_test.go`
- Modify: `backend/internal/adapters/agent/claudecode/claudecode.go`, `backend/internal/adapters/agent/codex/codex.go`, `backend/internal/lifecycle/manager.go`, `backend/internal/observe/reaper/reaper.go`, `backend/internal/service/session/status.go` — remove the `SessionMode` reads

**Interfaces:**
- Consumes: nothing outside these files still names `ports.Chat*` or `domain.SessionMode` after Tasks 6, 7 and 10.
- Produces: a domain with no conversation concept. Task 12 drops the tables these types mapped to.

- [ ] **Step 1: Confirm the remaining reference set**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rln "ports\.Chat" backend --include='*.go' | sort
grep -rln "SessionModeChat\|SessionModeTUI\|domain\.SessionMode" backend --include='*.go' | sort
```

Everything printed must be in the **Files** list above. If a file appears that is not listed, stop and report it before deleting — an unlisted reader means the mode is load-bearing somewhere this plan did not find.

- [ ] **Step 2: Delete the type files**

```bash
cd /Users/omaraly/development/AI/Operator
git rm backend/internal/ports/chat.go \
       backend/internal/domain/conversation.go \
       backend/internal/domain/sessionmode.go \
       backend/internal/domain/sessionmode_test.go \
       backend/internal/storage/sqlite/store/conversation_store.go \
       backend/internal/storage/sqlite/store/conversation_branch_store_test.go \
       backend/internal/storage/sqlite/store/conversation_history_store_test.go
```

- [ ] **Step 3: Collapse the mode reads in the five remaining files**

```bash
cd /Users/omaraly/development/AI/Operator/backend && go build ./... 2>&1 | head -30
```

Each reported site branched on chat versus TUI. Keep the TUI branch and delete the branch itself — do not leave an `if true`.

- [ ] **Step 4: Verify**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go test ./... 2>&1 | grep -c "^FAIL"
cd /Users/omaraly/development/AI/Operator && grep -rn "ports\.Chat\|domain\.SessionMode" backend --include='*.go' | wc -l
```

Expected: `0` failures and `0` references.

- [ ] **Step 5: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend
git commit -m "$(cat <<'MSG'
feat(backend)!: remove the chat ports and domain vocabulary

BREAKING CHANGE: ChatDriver, ChatCapability, ConversationUsage and
SessionMode no longer exist.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 12: Drop the conversation schema

Nine tables plus two columns. The store was emptied in Phase 1 — the production database confirms `conversations = 0` — so this is schema only, with no data migration.

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0101_drop_conversations.sql`
- Delete: `backend/internal/storage/sqlite/queries/conversations.sql`, `queries/session_interface_transitions.sql`
- Delete: `backend/internal/storage/sqlite/gen/conversations.sql.go`, `gen/session_interface_transitions.sql.go`
- Modify: `backend/internal/storage/sqlite/gen/models.go` (regenerated)
- Modify: `backend/internal/storage/sqlite/migrate_burned_versions_test.go` — add the `101` entry

**Interfaces:**
- Consumes: no Go code reads these tables after Task 11.
- Produces: the final schema. Nothing depends on this task.

- [ ] **Step 1: Confirm the tables are empty in the live databases**

```bash
for DB in ~/.operator/data/opr.db ~/.operator/dev/data/opr.db; do
  echo "== $DB"
  sqlite3 "$DB" "select 'conversations', count(*) from conversations;"
  sqlite3 "$DB" "select 'transitions', count(*) from session_interface_transitions;"
done
```

Expected: zero everywhere. A non-zero count means Phase 1's clear did not run on that database — stop and report rather than dropping rows.

- [ ] **Step 2: Write the migration**

```sql
-- +goose Up
ALTER TABLE sessions DROP COLUMN session_mode;
ALTER TABLE app_settings DROP COLUMN default_session_mode;
DROP TABLE IF EXISTS session_interface_transition_messages;
DROP TABLE IF EXISTS session_interface_transitions;
DROP TABLE IF EXISTS conversation_provider_events;
DROP TABLE IF EXISTS conversation_activities;
DROP TABLE IF EXISTS conversation_messages;
DROP TABLE IF EXISTS conversation_turns;
DROP TABLE IF EXISTS conversation_branches;
DROP TABLE IF EXISTS conversations;

-- +goose Down
SELECT 1;
```

The down migration is deliberately inert: the spec records Phase 4 as irreversible in practice, and a down that recreated nine empty tables would be a lie about recoverability.

- [ ] **Step 3: Delete the queries and regenerate**

```bash
cd /Users/omaraly/development/AI/Operator
git rm backend/internal/storage/sqlite/queries/conversations.sql \
       backend/internal/storage/sqlite/queries/session_interface_transitions.sql \
       backend/internal/storage/sqlite/gen/conversations.sql.go \
       backend/internal/storage/sqlite/gen/session_interface_transitions.sql.go
cd /Users/omaraly/development/AI/Operator && npm run sqlc && gofmt -l backend/internal/
```

- [ ] **Step 4: Register the migration in the burned-versions test**

Add `101: "0101_drop_conversations.sql"` to the map in `migrate_burned_versions_test.go`. If `gofmt` realigns the map because the keys changed width, that realignment is expected and belongs in this commit.

- [ ] **Step 5: Verify the migration applies to a real database**

```bash
cd /Users/omaraly/development/AI/Operator
cp ~/.operator/dev/data/opr.db /tmp/phase4-check.db
mkdir -p /tmp/phase4-check && cp /tmp/phase4-check.db /tmp/phase4-check/opr.db
cd backend && mkdir -p internal/tmpmigratecheck
cat > internal/tmpmigratecheck/main.go <<'EOF'
package main

import (
	"fmt"
	"os"

	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
)

func main() {
	if _, err := sqlite.Open(os.Args[1]); err != nil {
		fmt.Fprintln(os.Stderr, "migrate:", err)
		os.Exit(1)
	}
	fmt.Println("migrations applied")
}
EOF
go run ./internal/tmpmigratecheck /tmp/phase4-check
rm -rf internal/tmpmigratecheck
sqlite3 /tmp/phase4-check/opr.db "select max(version_id) from goose_db_version;"
sqlite3 /tmp/phase4-check/opr.db "select count(*) from sqlite_master where name in ('conversations','conversation_turns','session_interface_transitions');"
sqlite3 /tmp/phase4-check/opr.db "pragma integrity_check;"
```

Expected: `migrations applied`, version `101`, table count `0`, `ok`. Delete `/tmp/phase4-check*` afterwards, and confirm `git status --short` shows no stray `internal/tmpmigratecheck`.

- [ ] **Step 6: Verify the suite**

```bash
cd /Users/omaraly/development/AI/Operator/backend
gofmt -l internal/ && go vet ./... && go test ./... 2>&1 | grep -c "^FAIL"
```

Expected: `0`.

- [ ] **Step 7: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A backend
git commit -m "$(cat <<'MSG'
feat(db)!: drop the conversation schema

BREAKING CHANGE: nine conversation tables, sessions.session_mode and
app_settings.default_session_mode are dropped. The down migration is inert:
this phase is not reversible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 13: Full-tree verification and documentation

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `DESIGN.md`, `docs/architecture.md`, `docs/STATUS.md` — remove chat/ACP descriptions
- Modify: `docs/mobile-parity-ledger.md` — mark the chat files as removed in Phase 4
- Create: `docs/superpowers/plans/2026-09-06-phase-4-report.md`

**Interfaces:**
- Consumes: every prior task.
- Produces: the completion report.

- [ ] **Step 1: Prove no reference survives anywhere**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn "chatdriver\|ChatDriver\|acp-runtime\|SessionModeChat\|/conversation" \
  backend/internal backend/cmd frontend/src packages/mobile/lib packages/mobile/test \
  .github package.json 2>/dev/null | grep -v node_modules | sort
```

Expected: no output. Any hit is unfinished work, not an acceptable remnant.

- [ ] **Step 2: Run every gate**

```bash
R=/Users/omaraly/development/AI/Operator
cd $R/backend && gofmt -l internal/ && go vet ./... && go test ./... 2>&1 | grep -c "^FAIL"
golangci-lint cache clean
cd $R && npm run lint 2>&1 | tail -5
cd $R/packages/mobile && flutter analyze && flutter test 2>&1 | tail -3
cd $R/frontend && npm run typecheck && npm run lint && npm test 2>&1 | tail -5
cd $R && npm run api && git diff --stat backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
```

Expected: `0` Go failures, `0 issues` from lint after the cache clean, `No issues found!` from Flutter, green Dart and TS suites, and an **empty** diff from `npm run api` — a non-empty diff means Task 6 did not regenerate.

- [ ] **Step 3: Update the documentation**

```bash
cd /Users/omaraly/development/AI/Operator
grep -rn -i "chat mode\|chat driver\|ACP\|session mode" CLAUDE.md AGENTS.md DESIGN.md docs/architecture.md docs/STATUS.md | head -30
```

Rewrite each hit to describe the single-mode architecture. Do not leave "chat mode is deprecated" wording — the mode does not exist.

- [ ] **Step 4: Write the report**

Create `docs/superpowers/plans/2026-09-06-phase-4-report.md` recording: the measured line count deleted per area, the final gate output verbatim, the migration verification from Task 12 Step 5, and anything that diverged from this plan. No placeholders.

- [ ] **Step 5: Measure what was actually removed**

```bash
cd /Users/omaraly/development/AI/Operator
git diff --shortstat <first-commit-of-this-branch>^..HEAD
```

Put the number in the report.

- [ ] **Step 6: Commit**

```bash
cd /Users/omaraly/development/AI/Operator
git add -A
git commit -m "$(cat <<'MSG'
docs: record phase 4 (ACP removal) complete

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 7: Live verification before finishing the branch**

Restart the daemon **from the desktop app**, not from an agent shell — an agent shell leaks `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `ANTHROPIC_BASE_URL` and about thirty other variables into the spawned agent and kills it within a second. Then confirm on the desktop and the phone: a session spawns, the terminal attaches, the blocks view renders, the command row acts, and the context and quota readouts still populate. Record the result in the report before merging.

---

## Rollback

Every task is one commit and the branch is not pushed until Task 13. Reverting a single task is `git revert`; abandoning the phase is deleting the branch. After Task 12 lands and a daemon has run against a database, the schema drop is not revertible — the down migration is deliberately inert, and the spec records that reversing Phase 4 means rebuilding, not reverting. Do not run Task 12 against a database you have not copied first.
