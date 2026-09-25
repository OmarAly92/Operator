# Mobile composer: two-row field, Add context sheet, permission mode — design

Date: 2026-09-26. Package `packages/mobile` and daemon `backend/`. Approved in chat on 2026-09-26.

User asks, verbatim in substance:

- Make the chat field look like the reference: the text on the top line; underneath, from left to right, the **+** (attachment) button, the model chip, then the mic and send/stop on the right.
- Tapping **+** opens a bottom sheet like Claude iOS's "Add context", with everything except Connectors: Camera, Photos, Files, "Show recent photos", and a Permission row.
- The Permission row shows every mode and the user picks one. The default is Bypass.
- Keep the field's glass exactly as it is now. Change the daemon where needed. Work on its own branch.

## Facts established by reading the code (2026-09-26)

- **The composer is text-only today.** `terminal_composer.dart` has a text field, dictation, the slash menu, the model chip, and stop/send. The lightning "Session actions" button was removed on 2026-09-26. The send request is `{message}` only (`send_session_message_params.dart`).
- **Attachments exist in the daemon and are unused by the phone.**
  - `POST /api/v1/sessions/{id}/attachments` (`controllers/sessions_stage_attachments.go:20-53`) takes base64 JSON `{attachments:[{mimeType,data}]}`.
  - Limits: 8 files, 10 MiB each, 25 MiB total (`sessions.go:56-69`). SVG is refused.
  - It writes `<worktree>/<attachmentsDir>/attachment-<hex>.<ext>` and returns worktree-relative paths. The caller then names those paths in a normal `/send`.
  - `EndPoints.sessionAttachments` is defined in the app but has no caller.
- **The pickers are installed.** `image_picker ^1.2.3` and `file_selector ^1.1.0` are in the pubspec, unused. `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are in Info.plist. No recent-photos library is present.
- **Permission mode can only be set at spawn.**
  - `domain.PermissionMode` has `default`, `accept-edits`, `auto` and `bypass-permissions` (`domain/agentconfig.go:9-19`). There is no `plan`.
  - The Claude Code adapter maps these to `--permission-mode` at spawn and resume (`claudecode.go:252-257, 454-476`).
  - The transcript's `mode` and `permission-mode` records are discarded (`transcript.go:50-59`).
  - Session commands are only `stop`, `compact` and `model` (`domain/sessioncommand.go`).
  - The phone neither shows nor sets the mode.

## Design

### 1. The field (mobile)

- **Layout:** the glass capsule keeps its current look and growth. Inside it:
  - **Row 1** is the text field across the full width, with the placeholder as today.
  - **Row 2**, from left: a round glass **+** button, the model chip (the existing chip, restyled as a pill like the reference), a flexible gap, the mic, then send or stop (the existing buttons).
- **Attachment tray:** selected attachments show above the text as 56 pt rounded thumbnails, or as a file card for non-images. Each has a remove ×. The tray scrolls horizontally, and the field grows to fit.
- **Limits:** the app blocks going over the daemon's limits (8 files, 10 MiB each, 25 MiB total) with an inline message, and refuses SVG.
- **Send:** when attachments are present, the app stages them with `POST /attachments`, then sends the message with the returned paths appended on their own lines. The paths go in exactly the format the desktop uses, found by reading the desktop's send path.
  - While staging, the send button shows progress.
  - On failure the message and attachments stay put, and an inline error explains why.
  - A message may be attachments only, with no text.
- The shell-only composer (terminal sessions) gets no **+**.

### 2. "Add context" sheet (mobile)

This is an `AppSheet` in the existing glass style, titled **Add context** with a close button.

- **Three tiles:**
  - **Camera:** `image_picker`, camera source
  - **Photos:** `image_picker` multi-image
  - **Files:** `file_selector`, any type
  - Each adds to the tray and closes the sheet.
- **Show recent photos:** a row that expands, with `Disclosure` motion, into a horizontal strip of the latest 30 photos.
  - It uses `photo_manager`, a new dependency, and needs limited or full photo-library permission.
  - Tapping a thumbnail toggles it in the tray. The sheet stays open, with a checkmark on selected thumbnails.
  - If access is denied, the row reads "Allow photo access" and opens Settings.
- **Permission · <current mode> ›:** pushes a page inside the sheet, the same way existing sheets push pages. It lists every mode, with a check on the current one:
  - **Bypass permissions**
  - **Auto**
  - **Accept edits**
  - **Plan**
  - **Ask** (default)

  Choosing a mode applies it to this session (see 3). If that fails, the row reverts and shows an inline error.
- No Connectors.

### 3. Permission mode (daemon + mobile)

- **Domain:** add `plan` to `domain.PermissionMode`. The Claude Code adapter maps it to `--permission-mode plan`.
- **Knowing the live mode:**
  - The Claude Code transcript mapper stops discarding `permission-mode` records. It records the session's current mode and publishes a new block event, `permission_mode`, with the detail `{mode}`.
  - The session DTO gains `permissionMode`, the latest known mode. It falls back to the launch mode.
  - Before building this, the exact shape of the record is checked against real Claude Code 2.1.x transcripts under `~/.claude/projects`, with the paths redacted in fixtures. If the record does not exist in the pinned version, the fallback is the pane-drive screen read described next.
- **Changing it live:** a new session command, `permission-mode`, with `{mode}`.
  - **If the target is in the session's Shift+Tab cycle:** the daemon drives the pane under the existing exclusive per-session pane drive, the same machinery as the task Stop. It sends Shift+Tab (`ESC [ Z`) until the confirmed mode, from the transcript record or the parsed status line, equals the target. It stops at 6 presses.
    - The cycle is Default → Accept edits → Plan, plus Bypass when the session was launched with it.
    - Mux input is refused during the drive, and REST send gets 409 `SESSION_BUSY`.
  - **If the target is outside the cycle** (Auto, or Bypass on a session not launched in Bypass): the daemon restarts the agent with `--resume` and the new `--permission-mode`, using the existing resume path.
    - It is refused while the agent is working (409 `SESSION_BUSY`), so a live turn is never interrupted.
    - The phone says "Restarts the agent; the conversation continues" under those options.
  - **Errors:** upper-case codes, `PERMISSION_MODE_UNSUPPORTED`, `PERMISSION_MODE_UNCONFIRMED` and `SESSION_BUSY`, in the locked `{error, code, message, requestId}` envelope.
  - **Version gate:** the command is allow-listed to the verified Claude Code version, like the agent stop. On any other version it returns `PERMISSION_MODE_UNSUPPORTED`.
- **Default is Bypass:**
  - New sessions spawned from the phone default to `bypass-permissions` in the Spawn options sheet, and the choice is shown there.
  - The daemon's own default for other clients is unchanged.
- **Harnesses:** other harnesses (e.g. Codex) do not show the Permission row unless the daemon reports that they support it (`capabilities.permissionMode`).

## Out of scope

- Connectors.
- Sending image bytes inline in the message. The daemon's path design stays.
- Changing the mode of a session the phone did not open. The command is per session.

## Testing

- **Mobile:**
  - widget tests for the two-row layout, the + opening the sheet, the tray (add, remove, limits, SVG refused), and send with attachments (stage, then send with paths, and failure keeping the draft)
  - the recent-photos denied state, and the permission page (current check, choose, failure revert)
  - the Bypass default in Spawn options
  - pure tests for the path-append format
- **Daemon:**
  - transcript mapping of `permission-mode` records (real-shaped fixture)
  - the `permission_mode` event and DTO field
  - the command, cycle driving (fake pane), unconfirmed, busy refusal, and restart-with-resume for off-cycle targets
  - the version gate and the `plan` flag mapping
  - OpenAPI and TS regenerated
- **Simulator (dark and light):**
  - the field empty, typed, and with attachments
  - the sheet, the recent-photos strip, and the permission page
  - a real send with a photo to an idle session, confirming that the agent reads the file
  - a live mode change on a real Claude Code session
- **Gates:** `flutter analyze` prints "No issues found!", `flutter test` passes, and `go build`, `go vet`, `go test` and golangci-lint pass.
