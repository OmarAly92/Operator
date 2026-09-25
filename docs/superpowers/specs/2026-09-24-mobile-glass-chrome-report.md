# Mobile glass chrome, sheets, chat polish and background tasks: report

Branch `feat/mobile-ios-polish` (worktree `/Users/omaraly/development/AI/Operator-ios-polish`), from `a119690d7`. It contains `development` merged in at `332bc127f`. Nothing is merged into `development` or pushed yet.

## What shipped

| Area | Spec | What the user sees |
|---|---|---|
| Glass chrome | `2026-09-24-mobile-glass-chrome-design.md` | Floating glass tab bar, glass app bar, content under the bars, glass **+** button. |
| Sheets | `2026-09-24-mobile-sheets-design.md` | Sheets in the T3 style:<br>• opaque floating surface and grabber<br>• frosted header that fades in on scroll<br>• pages pushed inside the sheet, UIKit-style (350ms, parallax)<br>• a glass search capsule on the project, agent and account pickers<br>• the connection menu with a Rename page<br>• one Spawn options sheet |
| Chat polish | `2026-09-24-mobile-chat-polish-design.md` | Nine ideas taken from T3:<br>• glass composer that grows into a card, with the model chip; Stop sits beside the mic<br>• glass header that frosts on scroll<br>• floating "Working" pill and jump-to-latest chevron<br>• copy and time rows<br>• fresh-only reply fade<br>• "Worked for" turn fold<br>• animated disclosures<br>• shimmering Thinking row<br>• streaming haptics |
| Background tasks | chat-polish ledger, Tasks 8–10 | "✳ N running tasks" bubble at the end of the chat. Tapping it opens a Background tasks sheet that matches the Claude app:<br>• collapsible Running and Finished sections<br>• agent and shell cards<br>• a live timer and View transcript<br>• a per-task stop |
| Daemon | chat-polish ledger, Task 9; `docs/architecture.md` | `task_update` events built from Claude Code transcripts, `GET /api/v1/sessions/{id}/tasks`, and `POST …/tasks/{taskId}/stop`.<br>• **Shells:** stopped by signalling the process group that writes the task's own output file.<br>• **Agents:** stopped by driving Claude Code's `/tasks` panel through the pty, under an exclusive per-session pane drive, allow-listed to Claude Code 2.1.280. |
| Visual fixes | chat-polish ledger, Task 11 | Six issues from the screenshot pass:<br>• pill clearance and a bottom fade band<br>• edge effects only when content is scrolled under<br>• text-safe green in light mode (`accentText`, `attentionText`, 5.1–6.4:1)<br>• edge leaks closed<br>• light-mode glass rim<br>• alignment and notification fixes<br>Dark mode's approved glass is pixel-identical. |

## Gates at HEAD

- `flutter analyze`: No issues found!
- `flutter test`: 1827 passed.
- `go build ./... && go vet ./... && go test ./...`: 141 packages ok. golangci-lint: 0 issues.
- `openapi.yaml` and `schema.ts` regenerate byte-identical. Every branch-own commit carries the Co-Authored-By trailer.
- The final whole-branch review found the branch ready to merge, after one fix round.

## Evidence

- Simulator screenshots, light and dark: `packages/mobile/build/final-v2/`, which has 34 screens, contact sheets and before/after crops in `compare/`.
- Earlier rounds are under `packages/mobile/build/chat-polish/t2`–`t8` and `build/glass-chrome/`.
- Agent and shell stop were verified on an isolated Operator daemon against a real Claude Code 2.1.280 session:
  - idle and mid-turn
  - with desktop keystrokes refused during the drive, and pings answered within about 1ms

## What remains

- **Live phone check of the bubble and stop.** Not yet run on the simulator, because no session had a background task. Start one, e.g. "run `sleep 120` in the background", then open the chat.
- **Agent stop is version-gated.** It covers Claude Code 2.1.280 only. Each new version must be verified before it is added to the allow-list, and this machine already reports a newer version.
- **Monitors can't be stopped.** Claude Code reports a monitor's output file only when it ends, and the unsafe command fallback was removed on purpose.
- **Residual pane-drive race.** A permission dialog appearing mid-drive is a known race. Closing it needs atomic read-then-write in the pty-host.
- **The model picker still reads the lagging output ring.** Same class of issue as the one the `/tasks` driver fixed.
- **`flutter build ios` fails on Xcode 27.** The Pods' iOS 12/13 deployment targets are rejected, and Flutter 3.44.5's architecture check then misreads the framework. The builder's workaround was `xcodebuild … IPHONEOS_DEPLOYMENT_TARGET=15.0`. CI (analyze and test) is unaffected. A proper fix needs a Flutter upgrade, or Xcode 26.
- **Cosmetic:**
  - a 4pt dimmed corner arc of the Spawn back button under the large sheet
  - a faint grid in the dark status-bar blur when zoomed
  - the fold chevron snaps when a turn first folds
- **Out of scope, per the specs:**
  - the four `showModalBottomSheet` sheets
  - the raw terminal renderer
  - GPU cost on a physical phone, not measured
- **Incident, 2026-09-25.** Restarting `tauri:dev` for the new daemon killed the dev pty-hosts, which share its process group. An in-progress turn was interrupted, and scratch-38/39 ended.
