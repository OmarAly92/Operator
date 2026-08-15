# Flutter Mobile Port — M4 (Terminal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A TUI session is usable end to end on the phone — open a `tui`-mode session from the
board, watch its PTY live over the mux socket, type into it with a composer and a control-key row,
scroll and pinch-zoom its grid, kill or restore it, open a plain worktree shell from a chat
session, and hand a session between the Chat and Terminal interfaces.

**Architecture:** One new feature, `lib/feature/terminal/`. Its spine is a **per-session
`TerminalCubit`** that owns an `xterm.dart` `Terminal` object and attaches it to the **existing**
core `MuxClient` terminal channel — no new transport, no second socket. The daemon owns the
authoritative grid; the phone reports its own natural fit and renders the daemon's grid scaled to
width. A second cubit, `InterfaceSwitchCubit`, polls the daemon's interface-transition endpoint and
is shared by the chat screen and the terminal screen, exactly as RN's `useInterfaceTransition` hook
is. Every module with RN test coverage lands logic-and-test first, before the widget that uses it.

**Tech Stack:** Everything from M3, plus `xterm: ^4.0.0` (terminal emulator + renderer). Transport
is the M1 `MuxClient` (`web_socket_channel`); REST is the M0 `DioConsumer`.

**Spec:** `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`

## Global Constraints

- Source spec: `docs/superpowers/specs/2026-08-12-flutter-mobile-port-design.md`.
- Source of truth for RN behavior: `packages/mobile_rn/` (frozen reference). File paths below are
  relative to `packages/mobile_rn/` unless stated otherwise. The three RN files this milestone
  ports are `lib/session/TerminalSessionScreen.tsx` (1,529 lines), `lib/session/sendRoute.ts`,
  `lib/session/keys.ts`, `lib/session/KeyRow.tsx`, `lib/session/Composer.tsx`,
  `lib/session/useInterfaceTransition.ts`, plus the shell/interface-transition half of
  `lib/chat/api.ts` and the terminal palette in `lib/theme.ts`.
- Conventions are the `flutter-knowledge` skill. Where the mirrored RN source contradicts it, the
  skill wins. Invoke `flutter-testing` before the first test file, exactly as M0–M3 did.
- Cubit only — never `Bloc` with events. Static-only classes are `sealed class X`. **No comments**
  except non-obvious business rules. Single quotes, `const` constructors, full 8-digit hex colors,
  `final` locals. No `flutter_screenutil` extensions outside `AppTextStyle`. No `drift`, no
  `freezed`, no `json_serializable`, no `build_runner`.
- **User-facing copy is inline English**, as in M0–M3. This app has no `LocaleKeys` catalogue for
  product copy (see `packages/mobile/lib/feature/chat/**`); do not introduce `easy_localization`
  keys for the strings in this plan.
- Verification after every task: `flutter analyze` clean and `flutter test` green, both run from
  `packages/mobile`. The app is not run or built as part of implementation — with exactly one
  exception, Task 1's spike, which is run on a real phone by the repository owner.
- **Baseline this plan starts from: `flutter analyze` → "No issues found!", `flutter test` →
  645/645 green** (measured on `master` at the M3 merge, 2026-08-14: M3's 644 plus the manual-connect route test that landed with it). Every
  task's expected count is baseline-plus-its-own; never let the suite shrink.
- Package name is `operator_mobile`; imports are `package:operator_mobile/...`.
- All app state resolves under `~/.operator` — unaffected by this milestone, called out per
  `AGENTS.md`'s hard rule for completeness.

## Baseline: M3 is on `master`

M3 was implemented on `worktree-flutter-mobile-m3` and merged into `master` on 2026-08-14, together
with a `MaterialPageRoute<bool>` fix for the manual-connect route that was sitting uncommitted in
the working tree. The merged tree verifies clean:

```bash
cd packages/mobile && flutter analyze && flutter test
```

"No issues found!" and 645/645 green. M4 branches from that commit (the
`superpowers:using-git-worktrees` skill creates the isolated workspace).

### New dependency: vendored locally, not pinned to pub.dev

```yaml
# packages/mobile/pubspec.yaml
environment:
  sdk: ^3.12.2
workspace:
  - packages/xterm
dependencies:
  xterm:   # resolved via the workspace member below, no version constraint
```

The plan originally called for `xterm: ^4.0.0` pinned from pub.dev (verified conflict-free:
`quiver 3.2.2` and `zmodem 0.0.6`, no downgrades). Before Task 1 ran, the project owner vendored
`xterm 4.0.0`'s source into `packages/mobile/packages/xterm` as a Dart pub workspace member — the
package has had no pub.dev release in about two years, and owning the source lets Tasks 12–14 patch
xterm's gesture/rendering code directly instead of working around a frozen dependency. This is a
deliberate, explicit deviation from the plan text; see the deviations table below. The vendored
package's own broken `test/`, 5.5 MB `example/`, and `.github/` were removed (stale `mockito`
usage against the current `mockito` resolution), and the app's `analysis_options.yaml` excludes
`packages/**` from analysis — the same isolation a pub.dev dependency would have gotten for free.
`webview_flutter` is **not** added; it is the fallback renderer and is only reached if Task 1's gate
fails (see below).

### The renderer decision, and what happens if the spike fails

The spec makes the spike the first task of M4 and binds the whole milestone to its outcome:

> Renderer is `xterm.dart`. The spike is the first task of M4 and is bounded to a throwaway
> prototype that renders a live shell and nothing else — no feature integration, no state
> management, deleted once the decision is made.

Tasks 2–17 are written against `xterm.dart`. **They are gated on Task 1 reporting PASS on all four
criteria.** If any criterion fails, stop after Task 1, do not start Task 2, and report the failing
criterion — the fallback (`webview_flutter` + xterm.js, porting the injected CSS/JS from
`TerminalSessionScreen.tsx`) changes only the widget behind the `TerminalSurface` contract defined
in Task 12, but it changes enough of Tasks 12–14 that they must be re-planned rather than adapted
in flight. Everything in Tasks 2–11 and 15–17 (transport, geometry, data layer, cubits, routing,
chat integration) is renderer-independent and survives either outcome.

### What M4 deliberately does not include

| Omitted | Why | Lands in |
|---|---|---|
| The globe button, `getPreview` polling, and the in-app browser overlay (`TerminalSessionScreen.tsx:593–617, 1267–1295`) | `preview` is M5 per the spec's build order. The status bar and app-bar action rows are built with that slot absent, not disabled. | M5 |
| The composer's `MicKey`, the voice strip, and all of `lib/voice/*` | `voice` is M5 per the spec's build order. | M5 |
| `lib/haptics.ts` calls on every key press, send, kill and restore | No milestone has ported haptics; M1–M3 dropped them at the same call sites (the chat composer's send is the precedent). Adding them for the terminal alone would make the app inconsistent, and the spec's ledger has no haptics row. | M6 parity sweep decides |
| Deep-linking straight to `/terminal` from a notification | `notification` and deep links are M5. The terminal is reachable from the board, from the chat menu, and from the session route. | M5 |

### Deliberate deviations from the RN reference

| RN source | What it does | Why M4 departs |
|---|---|---|
| `TerminalSessionScreen.tsx:551–557, 817–834` retains PTY bytes in `pendingOutputRef` while the xterm WebView remounts | A font or theme change remounts the WebView, so bytes arriving in the gap would be lost. | `xterm.dart`'s `Terminal` is a plain Dart object owned by `TerminalCubit`, not by the widget. Font size and theme are `TerminalView` parameters, so neither remounts anything and no buffer can drop bytes. The retention buffer, `xtermReadyRef` and the `key={term-${fontSize}-${scheme}}` remount all disappear. |
| `TerminalSessionScreen.tsx:707–742` constructs a **new** `MuxClient` per screen and disconnects it on unmount | RN's client is per-screen. | The Dart `MuxClient` is a core lazy singleton shared with the board (`SessionsCubit` connects it and subscribes to `sessions`). `TerminalCubit` therefore **never** calls `connect()` or `disconnect()` — calling `connect()` a second time would open a second socket and orphan the first. It calls `openTerminal` / `closeTerminal` only, and the client's own `_openTerminals` map re-opens the handle after a reconnect (`mux_client.dart:121–124`). |
| `TERMINAL_ENHANCE_JS` (`TerminalSessionScreen.tsx:41–498`), 457 lines of injected CSS/JS: touch interception, scrollbar hiding, `proposeDimensions` measurement, wheel synthesis for the alt buffer, the scroll-to-top button, textarea hardening | All of it exists to make xterm.js behave inside a WebView. | `xterm.dart` renders natively. Alt-buffer scrolling is built in — `TerminalScrollGestureHandler` sends real wheel events and falls back to arrow keys when the app does not track the mouse (`xterm-4.0.0/lib/src/ui/scroll_handler.dart:84–99`), which is precisely what `wheelTick`/`appDrivesScroll` hand-roll. The keyboard is suppressed with `readOnly: true, hardwareKeyboardOnly: true` instead of disabling a hidden textarea. Fit measurement and zoom are ported as **pure Dart geometry** (Tasks 5 and 6) instead of injected JS. |
| `reportFit()` calls `fitAddon.proposeDimensions()` after zeroing `viewport.scrollBarWidth` | xterm.js cannot measure a mobile overlay scrollbar and under-reports columns. | `TerminalFit.measureCell` lays out ten `m`s with a `TextPainter` — the same trick `xterm.dart` itself uses (`char_metrics.dart`) — and divides the available box by it. There is no scrollbar to subtract, so the phantom-column bug does not exist. `calcCharSize` is not exported by the package, so it is reimplemented rather than imported. |
| `Alert.alert` with three buttons for the Chat handoff (`TerminalSessionScreen.tsx:977–988`) | React Native's imperative alert takes N buttons. | `AppDialog.confirm` is binary, so Task 14 adds a dedicated `showInterfaceSwitchSheet` returning an `InterfaceSwitchChoice` enum. The three options and their exact copy are ported unchanged. |
| `openSessionShell` (`lib/chat/api.ts:254–272`) does the list-then-create dance in the API module | RN has no repository layer. | The reuse rule ("Back → Open shell returns to the same process instead of leaking a new shell") is real behavior, so it lands in `TerminalRepositoryImp.openSessionShell` with its own test, not in a data source and not at a call site. |
| `useInterfaceTransition` is a hook the chat screen and the terminal screen each instantiate | React hooks are per-component. | `InterfaceSwitchCubit` is provided **once** by the session route's `MultiBlocProvider`, so the chat branch and the terminal branch of `SessionRouteScreen` share one poller instead of two racing ones. |
| `app/session/[id].tsx` and `app/shell/[handleId].tsx` are two routes onto one screen | Expo Router addresses by path. | One `RoutesStrings.terminal` route carrying a `TerminalArgs`; the session route renders `TerminalScreen` inline for `mode == 'tui'`, mirroring how it already renders `ChatScreen` for `mode == 'chat'`. |
| `sendRoute.ts` and `keys.ts` live under `lib/session/`, and the spec's ledger maps `sendRoute.test.ts` to `test/feature/sessions/logic/send_route_test.dart` | RN's `session/` directory is the terminal screen's directory. | Both land under `lib/feature/terminal/logic/` with tests at `test/feature/terminal/logic/`. Their only consumer is the terminal screen, and the M3 plan already recorded this expectation ("M4 ports `keys.ts` and adds those cases to a `test/feature/terminal/logic/keys_test.dart`"). The ledger rows are satisfied; the path differs, and the ledger table at the end of this plan records that for M6's parity sweep. |

### Cross-feature imports introduced here, and why

`terminal` imports `SessionsCubit`/`SessionsRepository` from `sessions` (kill, restore, and the
board refresh a settled handoff triggers) and `sessionTitle`/`isTerminalStatus` from
`sessions/logic`. `chat` imports `InterfaceSwitchCubit` and `TerminalRepository` from `terminal`
(the conversation menu's "Open worktree shell" and "Open Terminal UI" rows) — the same direction RN
has, where `ChatSessionScreen.tsx` imports from `lib/session/`. Nothing in `terminal` imports from
`chat`.

## File structure

**New, under `packages/mobile/lib/`:**

| File | Responsibility |
|---|---|
| `core/app_themes/colors/terminal_palette.dart` | The terminal's own 16-colour ANSI palette + cursor/selection, light and dark, as an `xterm` `TerminalTheme`. Not part of `AppSkin`: agent TUIs own the meaning of the ANSI slots. |
| `feature/terminal/logic/keys.dart` | The eight control keys a phone keyboard lacks, with their escape sequences. |
| `feature/terminal/logic/send_route.dart` | Which channel a composed message takes, and what the PTY must receive. |
| `feature/terminal/logic/terminal_fit.dart` | Cell measurement, natural grid fit, fit-to-width scale. |
| `feature/terminal/logic/terminal_zoom.dart` | Pinch/pan state: scale clamping, focal anchoring, translation clamping, double-tap toggle. |
| `feature/terminal/logic/interface_transition.dart` | Transition phase vocabulary: active, cancellable, and the phase's user-facing sentence. |
| `feature/terminal/data/model/shell_terminal_model.dart` | A worktree shell handle. |
| `feature/terminal/data/model/interface_transition_model.dart` | One interface-transition record. |
| `feature/terminal/data/model/interface_transition_status_model.dart` | Support + current transition for a session. |
| `feature/terminal/data/model/params/open_session_shell_params.dart` | `POST /shell-terminals` body. |
| `feature/terminal/data/model/params/start_interface_transition_params.dart` | `POST …/interface-transition` body. |
| `feature/terminal/data/model/params/send_session_message_params.dart` | `POST …/send` body. |
| `feature/terminal/data/data_source/terminal_remote_data_source.dart` | The six REST calls the terminal needs. |
| `feature/terminal/data/repository/terminal_repository.dart` | Network-gated wrappers + the shell reuse rule. |
| `feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart` (+ `terminal_state.dart` part) | PTY attach, output, fit negotiation, sends, zoom, kill/restore. |
| `feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart` (+ `interface_switch_state.dart` part) | Poll/start/cancel the Chat↔Terminal handoff. |
| `feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart` | Scaffold, app bar, `BlocListener`. |
| `feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart` | Status bar + banner + surface + dock layout. |
| `…/widgets/terminal_status_bar.dart` | Status dot, `cols×rows`, zoom pair, Kill/Restore. |
| `…/widgets/terminal_surface.dart` | The renderer seam: `TerminalView` + fit reporting + pinch/pan. |
| `…/widgets/terminal_key_row.dart` | The eight-key row. |
| `…/widgets/terminal_composer.dart` | Field, route toggle, keyboard dismiss, send. |
| `…/widgets/terminal_dead_overlay.dart` | "Session terminated" / "Shell closed" panel. |
| `…/widgets/interface_switch_overlay.dart` | The "Switching to Chat" scrim card. |
| `…/widgets/interface_switch_sheet.dart` | The three-way drain/interrupt/cancel choice. |

**Modified:**

| File | Change |
|---|---|
| `pubspec.yaml` | `xterm: ^4.0.0`. |
| `core/api/api_request_helpers/end_points.dart` | `shellTerminals`, `shellTerminal(handleId)`, `sessionSend(id)`, `sessionInterfaceTransition(id)`. |
| `core/mux/mux_client.dart` | A `currentStatus` field so a late subscriber knows the socket is already open. |
| `core/app_routes/routes_strings.dart` | `terminal`. |
| `core/app_routes/app_router.dart` | The `/terminal` case; `InterfaceSwitchCubit` added to the session route. |
| `core/utils/service_locator.dart` | `_terminalFeatureSetup()`. |
| `feature/sessions/presentation/session_route/ui/session_route_screen.dart` | The `tui` branch renders `TerminalScreen` instead of the "not in this build yet" panel. |
| `feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart` | Two new rows: worktree shell, Terminal UI. |
| `feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart` | Handles both new menu actions. |
| `feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart` | The stopped/unavailable banners get their "Open shell" action back. |

---
### Task 1: The `xterm.dart` spike (throwaway, device-gated)

The one task in this milestone that runs the app. Everything it creates is deleted before the task
is committed; the only surviving artefacts are the pinned dependency and the recorded verdict.

**Files:**
- Modify: `packages/mobile/pubspec.yaml`
- Create (then delete in Step 6): `packages/mobile/lib/spike/terminal_spike.dart`
- Modify: `docs/superpowers/plans/2026-08-14-flutter-mobile-port-m4.md` (the "Spike outcome" section at the end)
- Test: none — this task is measured on a device, not in the suite.

**Interfaces:**
- Consumes: `MuxClient` (`core/mux/mux_client.dart`), `ServerConfigStore`, `SessionsRepository`.
- Produces: `xterm: ^4.0.0` in `pubspec.yaml`, and a PASS/FAIL verdict per criterion that gates Tasks 2–17.

- [ ] **Step 1: Add the dependency**

```bash
cd packages/mobile && flutter pub add xterm
```

Expected: `pubspec.yaml` gains `xterm: ^4.0.0`; `flutter pub get` resolves `xterm 4.0.0`,
`quiver 3.2.2`, `zmodem 0.0.6` and changes nothing else.

- [ ] **Step 2: Confirm the baseline is still green with the dependency in**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 645/645 green.

- [ ] **Step 3: Write the throwaway spike**

Create `packages/mobile/lib/spike/terminal_spike.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:xterm/xterm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CacheHelper.init();
  await ServiceLocator.init();
  await sl<ServerConfigStore>().load();
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: const SpikePicker(),
  );
}

class SpikePicker extends StatefulWidget {
  const SpikePicker({super.key});

  @override
  State<SpikePicker> createState() => _SpikePickerState();
}

class _SpikePickerState extends State<SpikePicker> {
  List<SessionModel> _sessions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await sl<SessionsRepository>().getBoard();
    result.when(
      onSuccess: (response) => setState(() => _sessions = response.data?.sessions ?? []),
      onFailure: (failure) => setState(() => _error = failure.message),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('xterm spike')),
    body: _error != null
        ? Center(child: Text(_error!))
        : ListView(
            children: [
              for (final session in _sessions)
                ListTile(
                  title: Text(session.id ?? ''),
                  subtitle: Text('${session.mode} · ${session.status}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SpikeTerminal(
                        id: session.id ?? '',
                        projectId: session.projectId,
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class SpikeTerminal extends StatefulWidget {
  const SpikeTerminal({super.key, required this.id, this.projectId});

  final String id;
  final String? projectId;

  @override
  State<SpikeTerminal> createState() => _SpikeTerminalState();
}

class _SpikeTerminalState extends State<SpikeTerminal> {
  final Terminal _terminal = Terminal(maxLines: 5000);
  final TerminalController _controller = TerminalController();
  final MuxClient _mux = sl<MuxClient>();
  StreamSubscription<TerminalEvent>? _events;
  final Map<int, Offset> _pointers = {};
  double _scale = 1;
  double _scaleStart = 1;
  double _pinchDistance = 0;
  String _grid = '';

  double _distance() {
    final points = _pointers.values.toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }

  @override
  void initState() {
    super.initState();
    _events = _mux.terminalEvents.where((event) => event.id == widget.id).listen(_onEvent);
    _terminal.onOutput = (data) => _mux.sendInput(widget.id, data, projectId: widget.projectId);
    _terminal.onResize = (cols, rows, _, _) {
      _mux.resize(widget.id, cols, rows, projectId: widget.projectId);
      // TerminalView resizes during layout, so this fires inside performLayout:
      // calling setState synchronously here is illegal and silently breaks the
      // route's rebuild pipeline for the rest of the session.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _grid = '$cols x $rows');
      });
    };
    _mux.connect();
    _mux.openTerminal(widget.id, projectId: widget.projectId);
  }

  void _onEvent(TerminalEvent event) {
    switch (event) {
      case TerminalDataEvent(:final bytes):
        _terminal.write(utf8.decode(bytes, allowMalformed: true));
      case TerminalResizeEvent(:final cols, :final rows):
        setState(() => _grid = 'daemon $cols x $rows');
      case TerminalErrorEvent(:final message):
        _terminal.write('\r\n[spike] $message\r\n');
      case TerminalExitedEvent(:final code):
        _terminal.write('\r\n[spike] exited $code\r\n');
      case TerminalOpenedEvent():
        break;
    }
  }

  Future<void> _copy() async {
    final range = _controller.selection;
    if (range == null) return;
    await Clipboard.setData(ClipboardData(text: _terminal.buffer.getText(range)));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('copied')));
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _mux.closeTerminal(widget.id, projectId: widget.projectId);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_grid),
      actions: [IconButton(onPressed: _copy, icon: const Icon(Icons.copy))],
    ),
    // A Listener, not a GestureDetector: a ScaleGestureRecognizer accepts
    // single-pointer contacts and wins the arena against xterm's own long-press
    // recognizer, which would kill selection. This mirrors Task 13's design, so
    // the spike measures the gesture stack the product will actually ship.
    body: Listener(
      onPointerDown: (event) {
        _pointers[event.pointer] = event.localPosition;
        if (_pointers.length == 2) {
          _scaleStart = _scale;
          _pinchDistance = _distance();
        }
      },
      onPointerMove: (event) {
        if (!_pointers.containsKey(event.pointer)) return;
        _pointers[event.pointer] = event.localPosition;
        if (_pointers.length < 2 || _pinchDistance <= 0) return;
        setState(() => _scale = (_scaleStart * (_distance() / _pinchDistance)).clamp(0.4, 1.0));
      },
      onPointerUp: (event) => _pointers.remove(event.pointer),
      onPointerCancel: (event) => _pointers.remove(event.pointer),
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.topLeft,
        child: TerminalView(
          _terminal,
          controller: _controller,
          theme: TerminalThemes.defaultTheme,
          textStyle: const TerminalStyle(fontSize: 12),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: Run it on a real phone against a real daemon**

```bash
cd packages/mobile && flutter run -t lib/spike/terminal_spike.dart --release
```

`--release` matters: criterion 3 is a performance judgement and a debug build's frame times are not
evidence. Pair the phone first if it is not already paired (the spike reads the M1 config).

- [ ] **Step 5: Judge the four criteria and record the verdict**

Measured against current behavior, i.e. the RN app on the same phone and the same session.

| # | Criterion | How to test it | Passes when |
|---|---|---|---|
| 1 | **Gesture parity** | Open a session running a full-screen TUI (Claude Code, or `vim`/`less` in a shell). One-finger drag up and down; then pinch with two fingers. | The one-finger drag scrolls (scrollback in a plain shell, the app's own scroll in a TUI) and the two-finger pinch scales the grid between shrink-to-fit and 1:1 — **and the two do not fight**: a pinch never scrolls, a drag never zooms. |
| 2 | **PTY fit negotiation** | With the phone as the only viewer, watch the title's grid readout and check the shell reflows to it. Then open the same session on the desktop app and watch the readout change to the desktop's grid. | The phone's reported grid reaches the daemon (the PTY reflows), and when a desktop viewer owns the authoritative size the phone renders that grid scaled to fit instead of imposing its own. |
| 3 | **Output bursts** | Run something noisy — `yes | head -100000`, or a real build. | Output stays smooth; no multi-second freeze, no dropped frames severe enough to make the screen unresponsive. |
| 4 | **Selection and copy** | Long-press on a line, drag to extend, tap the copy action, paste elsewhere. | A selection is visible, extends with the drag, and the copy action puts the selected text on the clipboard. If nothing highlights, check the gesture stack **before** blaming the renderer: any recognizer that claims the arena (a `GestureDetector` with `onScale*`, in particular) defeats xterm's own long-press. |

Record the outcome in the "Spike outcome" section at the end of this plan file: one line per
criterion, PASS or FAIL, with a sentence of evidence.

**Gate.** All four PASS → continue to Task 2. Any FAIL → **stop**. Do not start Task 2. Report the
failing criterion and what was observed; the `webview_flutter` + xterm.js fallback needs Tasks 12–14
re-planned before any of it is written.

- [ ] **Step 6: Delete the spike**

```bash
rm -rf packages/mobile/lib/spike
```

The spec bounds the spike to a throwaway prototype "deleted once the decision is made". Nothing in
Tasks 2–17 imports it.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 645/645 green.

```bash
git add packages/mobile/pubspec.yaml packages/mobile/pubspec.lock docs/superpowers/plans/2026-08-14-flutter-mobile-port-m4.md
git commit -m "chore(mobile): adopt xterm.dart after the M4 renderer spike"
```

---

### Task 2: The terminal palette

The terminal keeps its own palette: agent TUIs own the meaning of the ANSI slots, so these colours
are deliberately *not* `AppSkin` tokens. Ported verbatim from `lib/theme.ts:196–249`.

**Files:**
- Create: `packages/mobile/lib/core/app_themes/colors/terminal_palette.dart`
- Test: `packages/mobile/test/core/app_themes/terminal_palette_test.dart`

**Interfaces:**
- Consumes: `xterm`'s `TerminalTheme`.
- Produces: `sealed class TerminalPalette` with `static const TerminalTheme dark`,
  `static const TerminalTheme light`, and `static TerminalTheme forBrightness(Brightness)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/core/app_themes/terminal_palette_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart';

void main() {
  group('TerminalPalette.dark', () {
    test('collapses black into the background so a filled row draws no bar', () {
      expect(TerminalPalette.dark.black, const Color(0xFF0C0D10));
      expect(TerminalPalette.dark.background, const Color(0xFF0C0D10));
    });

    test('carries the ANSI hues', () {
      expect(TerminalPalette.dark.foreground, const Color(0xFFF4F5F7));
      expect(TerminalPalette.dark.cursor, const Color(0xFFF59F4C));
      expect(TerminalPalette.dark.red, const Color(0xFFF05D5E));
      expect(TerminalPalette.dark.green, const Color(0xFF44C97A));
      expect(TerminalPalette.dark.yellow, const Color(0xFFE5C34B));
      expect(TerminalPalette.dark.blue, const Color(0xFF5B9CFF));
      expect(TerminalPalette.dark.magenta, const Color(0xFFC678DD));
      expect(TerminalPalette.dark.cyan, const Color(0xFF56B6C2));
      expect(TerminalPalette.dark.white, const Color(0xFFD7DAE0));
      expect(TerminalPalette.dark.brightBlack, const Color(0xFF7F8792));
      expect(TerminalPalette.dark.brightWhite, const Color(0xFFF4F5F7));
    });
  });

  group('TerminalPalette.light', () {
    test('collapses black into the light background too', () {
      expect(TerminalPalette.light.black, const Color(0xFFF5F5F4));
      expect(TerminalPalette.light.background, const Color(0xFFF5F5F4));
    });

    test('darkens every hue rather than reusing the dark set', () {
      expect(TerminalPalette.light.foreground, const Color(0xFF24292F));
      expect(TerminalPalette.light.cursor, const Color(0xFFB45309));
      expect(TerminalPalette.light.red, const Color(0xFFA13C37));
      expect(TerminalPalette.light.green, const Color(0xFF2E6B3E));
      expect(TerminalPalette.light.blue, const Color(0xFF3B5AA6));
      expect(TerminalPalette.light.brightWhite, const Color(0xFF24292F));
    });
  });

  test('picks the palette by brightness', () {
    expect(TerminalPalette.forBrightness(Brightness.dark), same(TerminalPalette.dark));
    expect(TerminalPalette.forBrightness(Brightness.light), same(TerminalPalette.light));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/app_themes/terminal_palette_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart'`.

- [ ] **Step 3: Write the palette**

Create `packages/mobile/lib/core/app_themes/colors/terminal_palette.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

sealed class TerminalPalette {
  static TerminalTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  /// `black` is collapsed into the background on purpose: a TUI that fills a row
  /// with "black" must draw an invisible band, not a bar.
  static const TerminalTheme dark = TerminalTheme(
    cursor: Color(0xFFF59F4C),
    selection: Color(0x405B9CFF),
    foreground: Color(0xFFF4F5F7),
    background: Color(0xFF0C0D10),
    black: Color(0xFF0C0D10),
    red: Color(0xFFF05D5E),
    green: Color(0xFF44C97A),
    yellow: Color(0xFFE5C34B),
    blue: Color(0xFF5B9CFF),
    magenta: Color(0xFFC678DD),
    cyan: Color(0xFF56B6C2),
    white: Color(0xFFD7DAE0),
    brightBlack: Color(0xFF7F8792),
    brightRed: Color(0xFFFF7B7C),
    brightGreen: Color(0xFF62DF91),
    brightYellow: Color(0xFFF2D66D),
    brightBlue: Color(0xFF79B1FF),
    brightMagenta: Color(0xFFD99AEE),
    brightCyan: Color(0xFF79D4DF),
    brightWhite: Color(0xFFF4F5F7),
    searchHitBackground: Color(0xFFE5C34B),
    searchHitBackgroundCurrent: Color(0xFFF59F4C),
    searchHitForeground: Color(0xFF0C0D10),
  );

  static const TerminalTheme light = TerminalTheme(
    cursor: Color(0xFFB45309),
    selection: Color(0x403B5AA6),
    foreground: Color(0xFF24292F),
    background: Color(0xFFF5F5F4),
    black: Color(0xFFF5F5F4),
    red: Color(0xFFA13C37),
    green: Color(0xFF2E6B3E),
    yellow: Color(0xFF87660F),
    blue: Color(0xFF3B5AA6),
    magenta: Color(0xFF7B5799),
    cyan: Color(0xFF3D7A7A),
    white: Color(0xFF666D75),
    brightBlack: Color(0xFF4C535B),
    brightRed: Color(0xFF7E3330),
    brightGreen: Color(0xFF265231),
    brightYellow: Color(0xFF6B5108),
    brightBlue: Color(0xFF31487F),
    brightMagenta: Color(0xFF5F4476),
    brightCyan: Color(0xFF316061),
    brightWhite: Color(0xFF24292F),
    searchHitBackground: Color(0xFF87660F),
    searchHitBackgroundCurrent: Color(0xFFB45309),
    searchHitForeground: Color(0xFFF5F5F4),
  );
}
```

`selection` and the three `searchHit*` slots have no RN counterpart — xterm.js takes selection from
CSS and Operator never used its search addon — so they are derived: selection is the theme's own
blue at 25% alpha, and search hits reuse yellow/cursor with the background as the hit foreground.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/app_themes/terminal_palette_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 650/650 green.

```bash
git add packages/mobile/lib/core/app_themes/colors/terminal_palette.dart packages/mobile/test/core/app_themes/terminal_palette_test.dart
git commit -m "feat(mobile): port the terminal palette"
```

---

### Task 3: The control-key row's vocabulary

Ports `lib/session/keys.ts`. This closes the half of the ledger row `session/keyboardInset.test.ts`
that M3 left open (M3 ported `dockInset`; the RN test file also covers `CONTROL_KEYS`).

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/keys.dart`
- Test: `packages/mobile/test/feature/terminal/logic/keys_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class ControlKey extends Equatable {String label; String sequence; String hint;}` and
  `const List<ControlKey> kControlKeys`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/logic/keys_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';

void main() {
  group('kControlKeys', () {
    test('offers exactly the eight keys the row divides its width between', () {
      expect(kControlKeys, hasLength(8));
      expect(
        kControlKeys.map((key) => key.label).toList(),
        ['esc', 'tab', '^C', '←', '↑', '↓', '→', '↵'],
      );
    });

    test('carries the escape sequences the PTY expects', () {
      final byLabel = {for (final key in kControlKeys) key.label: key.sequence};
      expect(byLabel['esc'], '\x1b');
      expect(byLabel['tab'], '\t');
      expect(byLabel['^C'], '\x03');
      expect(byLabel['←'], '\x1b[D');
      expect(byLabel['↑'], '\x1b[A');
      expect(byLabel['↓'], '\x1b[B');
      expect(byLabel['→'], '\x1b[C');
      expect(byLabel['↵'], '\r');
    });

    test('labels every key for accessibility', () {
      expect(kControlKeys.every((key) => key.hint.isNotEmpty), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/logic/keys_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the module**

Create `packages/mobile/lib/feature/terminal/logic/keys.dart`:

```dart
import 'package:equatable/equatable.dart';

/// The daemon runs SanitizeControlChars on `POST /sessions/{id}/send`, which
/// strips every one of these — the mux is the only path for control bytes.
class ControlKey extends Equatable {
  const ControlKey({required this.label, required this.sequence, required this.hint});

  final String label;
  final String sequence;
  final String hint;

  @override
  List<Object?> get props => [label, sequence, hint];
}

const List<ControlKey> kControlKeys = [
  ControlKey(label: 'esc', sequence: '\x1b', hint: 'Escape'),
  ControlKey(label: 'tab', sequence: '\t', hint: 'Tab'),
  ControlKey(label: '^C', sequence: '\x03', hint: 'Interrupt'),
  ControlKey(label: '←', sequence: '\x1b[D', hint: 'Left'),
  ControlKey(label: '↑', sequence: '\x1b[A', hint: 'Up'),
  ControlKey(label: '↓', sequence: '\x1b[B', hint: 'Down'),
  ControlKey(label: '→', sequence: '\x1b[C', hint: 'Right'),
  ControlKey(label: '↵', sequence: '\r', hint: 'Enter'),
];
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/logic/keys_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 653/653 green.

```bash
git add packages/mobile/lib/feature/terminal packages/mobile/test/feature/terminal
git commit -m "feat(mobile): port the terminal control keys"
```

---

### Task 4: Send routing

Ports `lib/session/sendRoute.ts` and mirrors `lib/session/sendRoute.test.ts`. The RN module matches
on a structural `{status, code}`; the Dart port matches on `Failure.apiStatus`, which is where
`dio_error_handler.dart:37–43` puts the daemon's `code`.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/send_route.dart`
- Test: `packages/mobile/test/feature/terminal/logic/send_route_test.dart`

**Interfaces:**
- Consumes: `Failure` (`core/error_handling/failures/failure.dart`).
- Produces: `enum SendTarget { agent, terminal }`, `const String kAwaitingDecision`,
  `bool shouldRetryOnTerminal(Failure?)`, `SendTarget routeForSend(SendTarget, [Failure?])`,
  `String terminalPayload(String)`, and the three notice constants `kReroutedNotice`,
  `kTerminalModeNotice`, `kTerminalUnavailableNotice`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/logic/send_route_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';

Failure _failure({int? statusCode, String? code}) =>
    ServerFailure(error: 'x', message: 'x', statusCode: statusCode, apiStatus: code);

void main() {
  group('shouldRetryOnTerminal', () {
    test('retries when the daemon says the session is paused on a decision', () {
      expect(shouldRetryOnTerminal(_failure(statusCode: 409, code: kAwaitingDecision)), isTrue);
    });

    // The whole safety argument for auto-routing rests on this list. A dead
    // session has no PTY, so a "successful" write would swallow the user's text
    // and hide the real error behind a fake success.
    test('does NOT retry when there is no live PTY to write to', () {
      for (final code in const [
        'SESSION_TERMINATED',
        'AGENT_EXITED',
        'SESSION_NOT_FOUND',
        'SESSION_NOT_RESTORABLE',
      ]) {
        expect(shouldRetryOnTerminal(_failure(statusCode: 409, code: code)), isFalse);
      }
    });

    test('does not retry on auth, rate limiting, or an unrecognised failure', () {
      expect(shouldRetryOnTerminal(_failure(statusCode: 401)), isFalse);
      expect(shouldRetryOnTerminal(_failure(statusCode: 429)), isFalse);
      expect(shouldRetryOnTerminal(_failure(statusCode: 500, code: 'INTERNAL')), isFalse);
      expect(shouldRetryOnTerminal(null), isFalse);
    });

    test('does not retry when the server was never reached', () {
      expect(shouldRetryOnTerminal(ServerFailure.noNetwork()), isFalse);
    });
  });

  group('routeForSend', () {
    test('sends to the agent by default', () {
      expect(routeForSend(SendTarget.agent), SendTarget.agent);
    });

    test('honours the explicit terminal target', () {
      expect(routeForSend(SendTarget.terminal), SendTarget.terminal);
      expect(
        routeForSend(SendTarget.terminal, _failure(statusCode: 500, code: 'INTERNAL')),
        SendTarget.terminal,
      );
    });

    test('auto-engages the terminal route for a blocked prompt', () {
      expect(
        routeForSend(SendTarget.agent, _failure(statusCode: 409, code: kAwaitingDecision)),
        SendTarget.terminal,
      );
    });

    test('keeps ordinary failures on the agent route', () {
      expect(routeForSend(SendTarget.agent, _failure(statusCode: 401)), SendTarget.agent);
      expect(
        routeForSend(SendTarget.agent, _failure(statusCode: 409, code: 'SESSION_TERMINATED')),
        SendTarget.agent,
      );
    });
  });

  group('terminalPayload', () {
    test('submits the line with a carriage return', () {
      expect(terminalPayload('y'), 'y\r');
    });

    test('leaves single-line text otherwise untouched', () {
      expect(terminalPayload("git commit -m 'x'"), "git commit -m 'x'\r");
    });

    // The composer is multiline, so pasted text can carry newlines. A PTY reads
    // each one as Enter, which would answer a dialog with the first fragment and
    // feed the rest to whatever opened next.
    test('collapses interior newlines so one message submits once', () {
      expect(terminalPayload('yes,\nuse the second option'), 'yes, use the second option\r');
      expect(terminalPayload('a\r\nb'), 'a b\r');
      expect(terminalPayload('a\n\n\nb'), 'a b\r');
    });

    test('drops surrounding whitespace so there is no empty second submission', () {
      expect(terminalPayload('approve\n'), 'approve\r');
      expect(terminalPayload('\n approve \n'), 'approve\r');
    });

    test('still submits when the text is only newlines', () {
      expect(terminalPayload('\n\n'), '\r');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/logic/send_route_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the module**

Create `packages/mobile/lib/feature/terminal/logic/send_route.dart`:

```dart
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

/// The daemon's code for "paused on a permission decision". `POST
/// /sessions/{id}/send` refuses with it and advises answering in the terminal,
/// so that one code — and only that one — reroutes the send to the PTY.
const String kAwaitingDecision = 'SESSION_AWAITING_DECISION';

enum SendTarget { agent, terminal }

bool shouldRetryOnTerminal(Failure? failure) => failure?.apiStatus == kAwaitingDecision;

SendTarget routeForSend(SendTarget target, [Failure? failure]) {
  if (target == SendTarget.terminal) return SendTarget.terminal;
  return shouldRetryOnTerminal(failure) ? SendTarget.terminal : SendTarget.agent;
}

/// The trailing carriage return is the Enter the user would otherwise have to
/// press. Interior newlines collapse to spaces first: a PTY reads every one of
/// them as its own Enter, so one message must submit exactly once.
String terminalPayload(String text) =>
    '${text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim()}\r';

const String kReroutedNotice = 'Agent was paused on a prompt — sent straight to the terminal.';
const String kTerminalModeNotice = 'Sending composer text straight to the terminal.';
const String kTerminalUnavailableNotice = 'Terminal is not connected yet — text was not sent.';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/logic/send_route_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 666/666 green.

```bash
git add packages/mobile/lib/feature/terminal/logic/send_route.dart packages/mobile/test/feature/terminal/logic/send_route_test.dart
git commit -m "feat(mobile): port terminal send routing"
```

---
### Task 5: Terminal fit geometry

The Dart replacement for `reportFit()` / `applyScale()` in `TERMINAL_ENHANCE_JS`
(`TerminalSessionScreen.tsx:67–86, 119–127`). Pure functions, so the arithmetic that decides how
many columns the daemon is told about is testable without a device.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/terminal_fit.dart`
- Test: `packages/mobile/test/feature/terminal/logic/terminal_fit_test.dart`

**Interfaces:**
- Consumes: `TextStyle`, `TextPainter` from `package:flutter/painting.dart`.
- Produces:
  - `class TerminalGrid extends Equatable { final int cols; final int rows; }`
  - `Size measureCell(TextStyle style)`
  - `TerminalGrid naturalFit(Size available, Size cell)`
  - `double fitScale(TerminalGrid grid, Size cell, double availableWidth)`
  - `Size gridSize(TerminalGrid grid, Size cell)`

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/logic/terminal_fit_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cell = Size(8, 16);

  group('naturalFit', () {
    test('floors the box into whole cells', () {
      expect(naturalFit(const Size(400, 800), cell), const TerminalGrid(50, 50));
      expect(naturalFit(const Size(403, 807), cell), const TerminalGrid(50, 50));
    });

    test('never proposes an empty grid', () {
      expect(naturalFit(const Size(2, 2), cell), const TerminalGrid(1, 1));
      expect(naturalFit(Size.zero, cell), const TerminalGrid(1, 1));
    });

    test('survives an unmeasured cell instead of dividing by zero', () {
      expect(naturalFit(const Size(400, 800), Size.zero), const TerminalGrid(1, 1));
    });
  });

  group('fitScale', () {
    test('is 1:1 when the daemon grid already fits the width', () {
      expect(fitScale(const TerminalGrid(40, 20), cell, 400), 1);
    });

    // The daemon's grid is authoritative: when a co-viewing desktop makes it
    // wider than the phone, the phone shrinks the whole grid rather than
    // re-fitting and mis-drawing a full-screen TUI.
    test('shrinks to width when the daemon grid is wider than the phone', () {
      expect(fitScale(const TerminalGrid(100, 20), cell, 400), 0.5);
    });

    test('never magnifies past 1:1 and never returns zero', () {
      expect(fitScale(const TerminalGrid(10, 20), cell, 400), 1);
      expect(fitScale(const TerminalGrid(0, 0), cell, 400), 1);
      expect(fitScale(const TerminalGrid(100, 20), cell, 0), 1);
    });
  });

  test('gridSize multiplies the grid out by the cell', () {
    expect(gridSize(const TerminalGrid(80, 24), cell), const Size(640, 384));
  });

  test('measureCell returns a positive monospace cell', () {
    final size = measureCell(const TextStyle(fontSize: 12, fontFamilyFallback: ['Menlo', 'monospace']));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(size.width));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/logic/terminal_fit_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the module**

Create `packages/mobile/lib/feature/terminal/logic/terminal_fit.dart`:

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

class TerminalGrid extends Equatable {
  const TerminalGrid(this.cols, this.rows);

  final int cols;
  final int rows;

  @override
  List<Object?> get props => [cols, rows];
}

const String _probe = 'mmmmmmmmmm';

/// xterm.dart measures its own cell the same way (`char_metrics.dart`), but does
/// not export that helper, so the app measures with the identical probe.
Size measureCell(TextStyle style) {
  final painter = TextPainter(
    text: const TextSpan(text: _probe),
    textDirection: TextDirection.ltr,
  );
  painter.text = TextSpan(text: _probe, style: style);
  painter.layout();
  final size = Size(painter.width / _probe.length, painter.height);
  painter.dispose();
  return size;
}

TerminalGrid naturalFit(Size available, Size cell) {
  if (cell.width <= 0 || cell.height <= 0) return const TerminalGrid(1, 1);
  return TerminalGrid(
    max(1, (available.width / cell.width).floor()),
    max(1, (available.height / cell.height).floor()),
  );
}

Size gridSize(TerminalGrid grid, Size cell) =>
    Size(grid.cols * cell.width, grid.rows * cell.height);

double fitScale(TerminalGrid grid, Size cell, double availableWidth) {
  final natural = grid.cols * cell.width;
  if (natural <= 0 || availableWidth <= 0) return 1;
  return min(1, availableWidth / natural);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/logic/terminal_fit_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 674/674 green.

```bash
git add packages/mobile/lib/feature/terminal/logic/terminal_fit.dart packages/mobile/test/feature/terminal/logic/terminal_fit_test.dart
git commit -m "feat(mobile): port terminal fit geometry"
```

---

### Task 6: Pinch/pan geometry

The Dart replacement for the `Z` object in `TERMINAL_ENHANCE_JS`
(`TerminalSessionScreen.tsx:97–137`): clamped scale, focal-point anchoring, clamped translation,
double-tap toggle. Pure, because getting it wrong strands the user looking at empty canvas with no
way back.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/terminal_zoom.dart`
- Test: `packages/mobile/test/feature/terminal/logic/terminal_zoom_test.dart`

**Interfaces:**
- Consumes: `TerminalGrid` is *not* used here; the module is in pixel space.
- Produces:
  - `class TerminalZoomBox extends Equatable { final Size content; final Size view; }`
  - `class TerminalZoom extends Equatable { final double scale, dx, dy; }` with
    `bool isZoomed(double minScale)`
  - `TerminalZoom clampZoom(TerminalZoom zoom, TerminalZoomBox box, double minScale)`
  - `TerminalZoom scaleAround(TerminalZoom zoom, {required double scale, required Offset focal, required TerminalZoomBox box, required double minScale})`
  - `TerminalZoom panBy(TerminalZoom zoom, Offset delta, TerminalZoomBox box, double minScale)`
  - `TerminalZoom toggleZoom(TerminalZoom zoom, {required Offset focal, required TerminalZoomBox box, required double minScale})`

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/logic/terminal_zoom_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_zoom.dart';

void main() {
  const box = TerminalZoomBox(content: Size(800, 1200), view: Size(400, 600));
  const minScale = 0.5;
  const overview = TerminalZoom(scale: minScale);

  test('the overview is not zoomed; anything above it is', () {
    expect(overview.isZoomed(minScale), isFalse);
    expect(const TerminalZoom(scale: 0.9).isZoomed(minScale), isTrue);
  });

  group('scaleAround', () {
    test('keeps the content under the focal point fixed', () {
      final zoomed = scaleAround(
        overview,
        scale: 1,
        focal: const Offset(200, 300),
        box: box,
        minScale: minScale,
      );

      expect(zoomed.scale, 1);
      // The point under (200,300) was content (400,600) at 0.5; at 1:1 it must
      // still land on (200,300), so the offset is 200-400 = -200.
      expect(zoomed.dx, -200);
      expect(zoomed.dy, -300);
    });

    test('clamps to the fit scale and snaps back to a flush overview', () {
      final out = scaleAround(
        const TerminalZoom(scale: 1, dx: -200, dy: -300),
        scale: 0.1,
        focal: const Offset(200, 300),
        box: box,
        minScale: minScale,
      );

      expect(out, const TerminalZoom(scale: minScale));
    });

    test('never magnifies past 1:1', () {
      final out = scaleAround(overview, scale: 4, focal: Offset.zero, box: box, minScale: minScale);
      expect(out.scale, 1);
    });
  });

  group('panBy', () {
    test('moves with the finger while zoomed', () {
      final out = panBy(const TerminalZoom(scale: 1, dx: -200, dy: -300), const Offset(30, 40), box, minScale);
      expect(out.dx, -170);
      expect(out.dy, -260);
    });

    test('never pans past the content edges', () {
      final out = panBy(const TerminalZoom(scale: 1, dx: -10, dy: -10), const Offset(500, 500), box, minScale);
      expect(out.dx, 0);
      expect(out.dy, 0);

      final far = panBy(const TerminalZoom(scale: 1, dx: -10, dy: -10), const Offset(-5000, -5000), box, minScale);
      expect(far.dx, box.view.width - box.content.width);
      expect(far.dy, box.view.height - box.content.height);
    });

    test('is inert at the overview, where the grid already fits', () {
      expect(panBy(overview, const Offset(50, 50), box, minScale), overview);
    });
  });

  group('toggleZoom', () {
    test('goes to 1:1 at the tapped point from the overview', () {
      final out = toggleZoom(overview, focal: const Offset(200, 300), box: box, minScale: minScale);
      expect(out.scale, 1);
      expect(out.dx, -200);
    });

    test('returns to a flush overview when already zoomed', () {
      final out = toggleZoom(
        const TerminalZoom(scale: 1, dx: -200, dy: -300),
        focal: const Offset(10, 10),
        box: box,
        minScale: minScale,
      );
      expect(out, const TerminalZoom(scale: minScale));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/logic/terminal_zoom_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the module**

Create `packages/mobile/lib/feature/terminal/logic/terminal_zoom.dart`:

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

class TerminalZoomBox extends Equatable {
  const TerminalZoomBox({required this.content, required this.view});

  final Size content;
  final Size view;

  @override
  List<Object?> get props => [content, view];
}

class TerminalZoom extends Equatable {
  const TerminalZoom({this.scale = 1, this.dx = 0, this.dy = 0});

  final double scale;
  final double dx;
  final double dy;

  bool isZoomed(double minScale) => scale > minScale + 0.001;

  @override
  List<Object?> get props => [scale, dx, dy];
}

TerminalZoom clampZoom(TerminalZoom zoom, TerminalZoomBox box, double minScale) {
  if (!zoom.isZoomed(minScale)) return TerminalZoom(scale: minScale);
  final minDx = min(0.0, box.view.width - box.content.width * zoom.scale);
  final minDy = min(0.0, box.view.height - box.content.height * zoom.scale);
  return TerminalZoom(
    scale: zoom.scale,
    dx: zoom.dx.clamp(minDx, 0.0),
    dy: zoom.dy.clamp(minDy, 0.0),
  );
}

TerminalZoom scaleAround(
  TerminalZoom zoom, {
  required double scale,
  required Offset focal,
  required TerminalZoomBox box,
  required double minScale,
}) {
  final next = scale.clamp(minScale, 1.0);
  final contentX = (focal.dx - zoom.dx) / zoom.scale;
  final contentY = (focal.dy - zoom.dy) / zoom.scale;
  return clampZoom(
    TerminalZoom(
      scale: next,
      dx: focal.dx - contentX * next,
      dy: focal.dy - contentY * next,
    ),
    box,
    minScale,
  );
}

TerminalZoom panBy(TerminalZoom zoom, Offset delta, TerminalZoomBox box, double minScale) {
  if (!zoom.isZoomed(minScale)) return zoom;
  return clampZoom(
    TerminalZoom(scale: zoom.scale, dx: zoom.dx + delta.dx, dy: zoom.dy + delta.dy),
    box,
    minScale,
  );
}

TerminalZoom toggleZoom(
  TerminalZoom zoom, {
  required Offset focal,
  required TerminalZoomBox box,
  required double minScale,
}) => zoom.isZoomed(minScale)
    ? TerminalZoom(scale: minScale)
    : scaleAround(zoom, scale: 1, focal: focal, box: box, minScale: minScale);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/logic/terminal_zoom_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 683/683 green.

```bash
git add packages/mobile/lib/feature/terminal/logic/terminal_zoom.dart packages/mobile/test/feature/terminal/logic/terminal_zoom_test.dart
git commit -m "feat(mobile): port terminal pinch and pan geometry"
```

---

### Task 7: Interface-transition vocabulary

Ports the two exported predicates in `lib/session/useInterfaceTransition.ts:11–29` and the phase
copy in `TerminalSessionScreen.tsx:513–528`. Kept separate from the cubit so the phase table is
tested without a poller.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/logic/interface_transition.dart`
- Test: `packages/mobile/test/feature/terminal/logic/interface_transition_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `bool interfaceTransitionIsActive(String? phase)`,
  `bool interfaceTransitionIsCancellable(String? phase)`,
  `String interfaceTransitionLabel(String? phase)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/logic/interface_transition_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';

void main() {
  group('interfaceTransitionIsActive', () {
    test('covers every in-flight phase', () {
      for (final phase in const [
        'requested',
        'preflighting',
        'draining',
        'source_stopping',
        'source_stopped',
        'target_starting',
        'activating',
      ]) {
        expect(interfaceTransitionIsActive(phase), isTrue, reason: phase);
      }
    });

    test('is false once the transition settles, and for no transition at all', () {
      for (final phase in const ['completed', 'failed', 'cancelled', 'recovery_required']) {
        expect(interfaceTransitionIsActive(phase), isFalse, reason: phase);
      }
      expect(interfaceTransitionIsActive(null), isFalse);
      expect(interfaceTransitionIsActive('nonsense'), isFalse);
    });
  });

  group('interfaceTransitionIsCancellable', () {
    test('allows cancelling only before the source controller is stopped', () {
      expect(interfaceTransitionIsCancellable('requested'), isTrue);
      expect(interfaceTransitionIsCancellable('preflighting'), isTrue);
      expect(interfaceTransitionIsCancellable('draining'), isTrue);
      expect(interfaceTransitionIsCancellable('source_stopping'), isFalse);
      expect(interfaceTransitionIsCancellable('activating'), isFalse);
      expect(interfaceTransitionIsCancellable(null), isFalse);
    });
  });

  group('interfaceTransitionLabel', () {
    test('explains what is happening in each phase', () {
      expect(interfaceTransitionLabel('draining'), startsWith('Waiting for the current terminal turn'));
      expect(interfaceTransitionLabel('source_stopping'), startsWith('Stopping the terminal controller'));
      expect(interfaceTransitionLabel('source_stopped'), contains('worktree and native conversation are unchanged'));
      expect(interfaceTransitionLabel('target_starting'), startsWith('Resuming the same native conversation'));
      expect(interfaceTransitionLabel('activating'), 'Opening the Chat interface.');
    });

    test('falls back to the preflight sentence for an unknown or absent phase', () {
      const fallback = 'Checking that Chat can resume this agent\'s native conversation.';
      expect(interfaceTransitionLabel(null), fallback);
      expect(interfaceTransitionLabel('requested'), fallback);
      expect(interfaceTransitionLabel('nonsense'), fallback);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/logic/interface_transition_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the module**

Create `packages/mobile/lib/feature/terminal/logic/interface_transition.dart`:

```dart
const Set<String> _activePhases = {
  'requested',
  'preflighting',
  'draining',
  'source_stopping',
  'source_stopped',
  'target_starting',
  'activating',
};

const Set<String> _cancellablePhases = {'requested', 'preflighting', 'draining'};

bool interfaceTransitionIsActive(String? phase) => phase != null && _activePhases.contains(phase);

bool interfaceTransitionIsCancellable(String? phase) =>
    phase != null && _cancellablePhases.contains(phase);

String interfaceTransitionLabel(String? phase) => switch (phase) {
  'draining' =>
    'Waiting for the current terminal turn to finish. New Operator messages are queued safely.',
  'source_stopping' => 'Stopping the terminal controller before Chat starts.',
  'source_stopped' =>
    'Terminal controller stopped. The worktree and native conversation are unchanged.',
  'target_starting' => 'Resuming the same native conversation in Chat.',
  'activating' => 'Opening the Chat interface.',
  _ => 'Checking that Chat can resume this agent\'s native conversation.',
};
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/logic/interface_transition_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 688/688 green.

```bash
git add packages/mobile/lib/feature/terminal/logic/interface_transition.dart packages/mobile/test/feature/terminal/logic/interface_transition_test.dart
git commit -m "feat(mobile): port the interface-transition vocabulary"
```

---

### Task 8: Endpoints, models and params

Ports the wire shapes in `lib/chat/api.ts:34–95, 245–276` and the send body in `lib/api.ts:590–595`.
Every model field is nullable, per the conventions.

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/shell_terminal_model.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/interface_transition_model.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/interface_transition_status_model.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/params/open_session_shell_params.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/params/start_interface_transition_params.dart`
- Create: `packages/mobile/lib/feature/terminal/data/model/params/send_session_message_params.dart`
- Test: `packages/mobile/test/core/api/end_points_test.dart` (modify)
- Test: `packages/mobile/test/feature/terminal/data/model/terminal_models_test.dart`

**Interfaces:**
- Consumes: `Equatable`.
- Produces:
  - `EndPoints.shellTerminals`, `EndPoints.shellTerminal(String handleId)`,
    `EndPoints.sessionSend(String sessionId)`, `EndPoints.sessionInterfaceTransition(String sessionId)`.
  - `ShellTerminalModel(handleId, projectId, sessionId, workingDir, title, createdAt)` with
    `fromJson`, and `ShellTerminalModel.listFromJson(Map<String, dynamic>)`.
  - `InterfaceTransitionModel(id, sessionId, sourceMode, targetMode, policy, phase, errorCode, errorDetail, createdAt, updatedAt, completedAt)` with `fromJson`.
  - `InterfaceTransitionStatusModel(supported, targetMode, reasonCode, reason, transition)` with `fromJson`.
  - `OpenSessionShellParams(projectId, sessionId)`, `StartInterfaceTransitionParams(targetMode, policy)`,
    `SendSessionMessageParams(message)`, each with `toJson()`.

- [ ] **Step 1: Write the failing tests**

Append to `packages/mobile/test/core/api/end_points_test.dart`, inside its existing `main()`:

```dart
  test('builds the terminal paths', () {
    expect(EndPoints.shellTerminals, '/api/v1/shell-terminals');
    expect(EndPoints.shellTerminal('handle 1'), '/api/v1/shell-terminals/handle%201');
    expect(EndPoints.sessionSend('sess-1'), '/api/v1/sessions/sess-1/send');
    expect(
      EndPoints.sessionInterfaceTransition('sess-1'),
      '/api/v1/sessions/sess-1/interface-transition',
    );
  });
```

Create `packages/mobile/test/feature/terminal/data/model/terminal_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

void main() {
  group('ShellTerminalModel', () {
    test('parses a handle', () {
      final model = ShellTerminalModel.fromJson(const {
        'handleId': 'h-1',
        'projectId': 'p-1',
        'sessionId': 's-1',
        'workingDir': '/tmp/wt',
        'title': 'Worktree shell',
        'createdAt': '2026-08-14T10:00:00Z',
      });

      expect(model.handleId, 'h-1');
      expect(model.sessionId, 's-1');
      expect(model.title, 'Worktree shell');
    });

    test('tolerates a handle with nothing but an id', () {
      final model = ShellTerminalModel.fromJson(const {'handleId': 'h-1'});
      expect(model.handleId, 'h-1');
      expect(model.workingDir, isNull);
    });

    test('reads the list envelope, missing key included', () {
      expect(
        ShellTerminalModel.listFromJson(const {
          'shellTerminals': [
            {'handleId': 'h-1'},
            {'handleId': 'h-2'},
          ],
        }).map((shell) => shell.handleId).toList(),
        ['h-1', 'h-2'],
      );
      expect(ShellTerminalModel.listFromJson(const {}), isEmpty);
    });
  });

  group('InterfaceTransitionStatusModel', () {
    test('parses support, target mode and the nested transition', () {
      final status = InterfaceTransitionStatusModel.fromJson(const {
        'supported': true,
        'targetMode': 'chat',
        'transition': {
          'id': 't-1',
          'sessionId': 's-1',
          'sourceMode': 'tui',
          'targetMode': 'chat',
          'policy': 'drain',
          'phase': 'draining',
        },
      });

      expect(status.supported, isTrue);
      expect(status.targetMode, 'chat');
      expect(status.transition?.phase, 'draining');
      expect(status.transition?.policy, 'drain');
    });

    test('parses an unsupported session with a reason and no transition', () {
      final status = InterfaceTransitionStatusModel.fromJson(const {
        'supported': false,
        'targetMode': 'chat',
        'reasonCode': 'CHAT_DRIVER_UNAVAILABLE',
        'reason': 'This agent has no chat driver.',
      });

      expect(status.supported, isFalse);
      expect(status.reason, 'This agent has no chat driver.');
      expect(status.transition, isNull);
    });

    test('reads the transition envelope a start returns', () {
      final transition = InterfaceTransitionModel.fromJson(const {
        'id': 't-1',
        'phase': 'requested',
        'errorDetail': null,
      });
      expect(transition.id, 't-1');
      expect(transition.phase, 'requested');
      expect(transition.errorDetail, isNull);
    });
  });

  group('params', () {
    test('serialize exactly the daemon\'s bodies', () {
      expect(
        const OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1').toJson(),
        {'projectId': 'p-1', 'sessionId': 's-1'},
      );
      expect(
        const StartInterfaceTransitionParams(targetMode: 'chat', policy: 'interrupt').toJson(),
        {'targetMode': 'chat', 'policy': 'interrupt'},
      );
      expect(const SendSessionMessageParams(message: 'hi').toJson(), {'message': 'hi'});
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/api/end_points_test.dart test/feature/terminal/data/model/terminal_models_test.dart`
Expected: FAIL — `shellTerminals` is not defined; the model URIs do not exist.

- [ ] **Step 3: Add the endpoints**

In `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`, add beside the existing
members:

```dart
  static const String shellTerminals = '/api/v1/shell-terminals';

  static String shellTerminal(String handleId) =>
      '$shellTerminals/${Uri.encodeComponent(handleId)}';
  static String sessionSend(String sessionId) => '${_session(sessionId)}/send';
  static String sessionInterfaceTransition(String sessionId) =>
      '${_session(sessionId)}/interface-transition';
```

- [ ] **Step 4: Write the models**

Create `packages/mobile/lib/feature/terminal/data/model/shell_terminal_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class ShellTerminalModel extends Equatable {
  final String? handleId;
  final String? projectId;
  final String? sessionId;
  final String? workingDir;
  final String? title;
  final String? createdAt;

  const ShellTerminalModel({
    this.handleId,
    this.projectId,
    this.sessionId,
    this.workingDir,
    this.title,
    this.createdAt,
  });

  factory ShellTerminalModel.fromJson(Map<String, dynamic> json) => ShellTerminalModel(
    handleId: json['handleId'] as String?,
    projectId: json['projectId'] as String?,
    sessionId: json['sessionId'] as String?,
    workingDir: json['workingDir'] as String?,
    title: json['title'] as String?,
    createdAt: json['createdAt'] as String?,
  );

  static List<ShellTerminalModel> listFromJson(Map<String, dynamic> json) =>
      (json['shellTerminals'] as List<dynamic>? ?? [])
          .map((shell) => ShellTerminalModel.fromJson(shell as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [handleId, projectId, sessionId, workingDir, title, createdAt];
}
```

Create `packages/mobile/lib/feature/terminal/data/model/interface_transition_model.dart`:

```dart
import 'package:equatable/equatable.dart';

class InterfaceTransitionModel extends Equatable {
  final String? id;
  final String? sessionId;
  final String? sourceMode;
  final String? targetMode;
  final String? policy;
  final String? phase;
  final String? errorCode;
  final String? errorDetail;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;

  const InterfaceTransitionModel({
    this.id,
    this.sessionId,
    this.sourceMode,
    this.targetMode,
    this.policy,
    this.phase,
    this.errorCode,
    this.errorDetail,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  factory InterfaceTransitionModel.fromJson(Map<String, dynamic> json) => InterfaceTransitionModel(
    id: json['id'] as String?,
    sessionId: json['sessionId'] as String?,
    sourceMode: json['sourceMode'] as String?,
    targetMode: json['targetMode'] as String?,
    policy: json['policy'] as String?,
    phase: json['phase'] as String?,
    errorCode: json['errorCode'] as String?,
    errorDetail: json['errorDetail'] as String?,
    createdAt: json['createdAt'] as String?,
    updatedAt: json['updatedAt'] as String?,
    completedAt: json['completedAt'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    sessionId,
    sourceMode,
    targetMode,
    policy,
    phase,
    errorCode,
    errorDetail,
    createdAt,
    updatedAt,
    completedAt,
  ];
}
```

Create `packages/mobile/lib/feature/terminal/data/model/interface_transition_status_model.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';

class InterfaceTransitionStatusModel extends Equatable {
  final bool? supported;
  final String? targetMode;
  final String? reasonCode;
  final String? reason;
  final InterfaceTransitionModel? transition;

  const InterfaceTransitionStatusModel({
    this.supported,
    this.targetMode,
    this.reasonCode,
    this.reason,
    this.transition,
  });

  factory InterfaceTransitionStatusModel.fromJson(Map<String, dynamic> json) {
    final transition = json['transition'];
    return InterfaceTransitionStatusModel(
      supported: json['supported'] as bool?,
      targetMode: json['targetMode'] as String?,
      reasonCode: json['reasonCode'] as String?,
      reason: json['reason'] as String?,
      transition: transition is Map<String, dynamic>
          ? InterfaceTransitionModel.fromJson(transition)
          : null,
    );
  }

  @override
  List<Object?> get props => [supported, targetMode, reasonCode, reason, transition];
}
```

- [ ] **Step 5: Write the params**

Create `packages/mobile/lib/feature/terminal/data/model/params/open_session_shell_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class OpenSessionShellParams extends Equatable {
  final String projectId;
  final String sessionId;

  const OpenSessionShellParams({required this.projectId, required this.sessionId});

  Map<String, dynamic> toJson() => {'projectId': projectId, 'sessionId': sessionId};

  @override
  List<Object?> get props => [projectId, sessionId];
}
```

Create `packages/mobile/lib/feature/terminal/data/model/params/start_interface_transition_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class StartInterfaceTransitionParams extends Equatable {
  final String targetMode;
  final String policy;

  const StartInterfaceTransitionParams({required this.targetMode, required this.policy});

  Map<String, dynamic> toJson() => {'targetMode': targetMode, 'policy': policy};

  @override
  List<Object?> get props => [targetMode, policy];
}
```

Create `packages/mobile/lib/feature/terminal/data/model/params/send_session_message_params.dart`:

```dart
import 'package:equatable/equatable.dart';

class SendSessionMessageParams extends Equatable {
  final String message;

  const SendSessionMessageParams({required this.message});

  Map<String, dynamic> toJson() => {'message': message};

  @override
  List<Object?> get props => [message];
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/api/end_points_test.dart test/feature/terminal/data/model/terminal_models_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 696/696 green.

```bash
git add packages/mobile/lib/core/api/api_request_helpers/end_points.dart packages/mobile/lib/feature/terminal/data packages/mobile/test/core/api/end_points_test.dart packages/mobile/test/feature/terminal/data
git commit -m "feat(mobile): add the terminal wire shapes"
```

---
### Task 9: The terminal data source and repository

Six REST calls, plus the one piece of behavior that is not a passthrough: reusing an existing
session shell instead of leaking a new PTY on every visit (`lib/chat/api.ts:259–262`).

**Files:**
- Create: `packages/mobile/lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`
- Create: `packages/mobile/lib/feature/terminal/data/repository/terminal_repository.dart`
- Test: `packages/mobile/test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart`
- Test: `packages/mobile/test/feature/terminal/data/repository/terminal_repository_test.dart`

**Interfaces:**
- Consumes: `ApiConsumer`, `NetworkStatus`, `GlobalResponse`, the Task 8 models and params.
- Produces:
  - `abstract class TerminalRemoteDataSource` / `TerminalRemoteDataSourceImp` with
    `getShellTerminals()`, `openShellTerminal(OpenSessionShellParams)`,
    `closeShellTerminal(String handleId)`, `sendSessionMessage(String, SendSessionMessageParams)`,
    `getInterfaceTransition(String)`, `startInterfaceTransition(String, StartInterfaceTransitionParams)`,
    `cancelInterfaceTransition(String)`.
  - `abstract class TerminalRepository` / `TerminalRepositoryImp` with the same method names, all
    returning `FutureResult<...>`, plus `openSessionShell(OpenSessionShellParams)` which reuses an
    existing handle.

- [ ] **Step 1: Write the failing data-source test**

Create `packages/mobile/test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

void main() {
  late _MockApiConsumer apiConsumer;
  late TerminalRemoteDataSource dataSource;

  setUp(() {
    apiConsumer = _MockApiConsumer();
    dataSource = TerminalRemoteDataSourceImp(apiConsumer);
  });

  test('lists shell terminals', () async {
    when(() => apiConsumer.get(any())).thenAnswer(
      (_) async => _response({
        'shellTerminals': [
          {'handleId': 'h-1', 'sessionId': 's-1'},
        ],
      }),
    );

    final shells = (await dataSource.getShellTerminals()).data!;

    expect(shells.single.handleId, 'h-1');
    verify(() => apiConsumer.get(EndPoints.shellTerminals)).called(1);
  });

  test('opens a shell with the project and session in the body', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _response({
        'shellTerminal': {'handleId': 'h-9', 'title': 'Worktree shell'},
      }),
    );

    final shell = (await dataSource.openShellTerminal(
      const OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1'),
    )).data!;

    expect(shell.handleId, 'h-9');
    final captured = verify(
      () => apiConsumer.post(EndPoints.shellTerminals, body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'projectId': 'p-1', 'sessionId': 's-1'});
  });

  test('closes a shell by handle', () async {
    when(() => apiConsumer.delete(any())).thenAnswer((_) async => _response(null));

    await dataSource.closeShellTerminal('h-9');

    verify(() => apiConsumer.delete(EndPoints.shellTerminal('h-9'))).called(1);
  });

  test('sends a message to the harness route, not the conversation route', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => _response(null));

    await dataSource.sendSessionMessage('s-1', const SendSessionMessageParams(message: 'go'));

    final captured = verify(
      () => apiConsumer.post(EndPoints.sessionSend('s-1'), body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'message': 'go'});
  });

  test('reads the interface-transition status', () async {
    when(() => apiConsumer.get(any())).thenAnswer(
      (_) async => _response({
        'supported': true,
        'targetMode': 'chat',
        'transition': {'id': 't-1', 'phase': 'draining'},
      }),
    );

    final status = (await dataSource.getInterfaceTransition('s-1')).data!;

    expect(status.supported, isTrue);
    expect(status.transition?.phase, 'draining');
    verify(() => apiConsumer.get(EndPoints.sessionInterfaceTransition('s-1'))).called(1);
  });

  test('starts a transition and unwraps the transition envelope', () async {
    when(() => apiConsumer.post(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => _response({
        'transition': {'id': 't-2', 'phase': 'requested'},
      }),
    );

    final transition = (await dataSource.startInterfaceTransition(
      's-1',
      const StartInterfaceTransitionParams(targetMode: 'chat', policy: 'drain'),
    )).data!;

    expect(transition.id, 't-2');
    final captured = verify(
      () => apiConsumer.post(
        EndPoints.sessionInterfaceTransition('s-1'),
        body: captureAny(named: 'body'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured, {'targetMode': 'chat', 'policy': 'drain'});
  });

  test('cancels a transition', () async {
    when(() => apiConsumer.delete(any())).thenAnswer((_) async => _response(null));

    await dataSource.cancelInterfaceTransition('s-1');

    verify(() => apiConsumer.delete(EndPoints.sessionInterfaceTransition('s-1'))).called(1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the data source**

Create `packages/mobile/lib/feature/terminal/data/data_source/terminal_remote_data_source.dart`:

```dart
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

abstract class TerminalRemoteDataSource {
  Future<GlobalResponse<List<ShellTerminalModel>>> getShellTerminals();
  Future<GlobalResponse<ShellTerminalModel>> openShellTerminal(OpenSessionShellParams params);
  Future<void> closeShellTerminal(String handleId);
  Future<void> sendSessionMessage(String sessionId, SendSessionMessageParams params);
  Future<GlobalResponse<InterfaceTransitionStatusModel>> getInterfaceTransition(String sessionId);
  Future<GlobalResponse<InterfaceTransitionModel>> startInterfaceTransition(
    String sessionId,
    StartInterfaceTransitionParams params,
  );
  Future<void> cancelInterfaceTransition(String sessionId);
}

class TerminalRemoteDataSourceImp implements TerminalRemoteDataSource {
  final ApiConsumer _apiConsumer;

  TerminalRemoteDataSourceImp(this._apiConsumer);

  @override
  Future<GlobalResponse<List<ShellTerminalModel>>> getShellTerminals() async {
    final response = await _apiConsumer.get(EndPoints.shellTerminals);
    return GlobalResponse<List<ShellTerminalModel>>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: ShellTerminalModel.listFromJson,
    );
  }

  @override
  Future<GlobalResponse<ShellTerminalModel>> openShellTerminal(
    OpenSessionShellParams params,
  ) async {
    final response = await _apiConsumer.post(EndPoints.shellTerminals, body: params.toJson());
    return GlobalResponse<ShellTerminalModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) =>
          ShellTerminalModel.fromJson(json['shellTerminal'] as Map<String, dynamic>? ?? const {}),
    );
  }

  @override
  Future<void> closeShellTerminal(String handleId) async {
    await _apiConsumer.delete(EndPoints.shellTerminal(handleId));
  }

  @override
  Future<void> sendSessionMessage(String sessionId, SendSessionMessageParams params) async {
    await _apiConsumer.post(EndPoints.sessionSend(sessionId), body: params.toJson());
  }

  @override
  Future<GlobalResponse<InterfaceTransitionStatusModel>> getInterfaceTransition(
    String sessionId,
  ) async {
    final response = await _apiConsumer.get(EndPoints.sessionInterfaceTransition(sessionId));
    return GlobalResponse<InterfaceTransitionStatusModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: InterfaceTransitionStatusModel.fromJson,
    );
  }

  @override
  Future<GlobalResponse<InterfaceTransitionModel>> startInterfaceTransition(
    String sessionId,
    StartInterfaceTransitionParams params,
  ) async {
    final response = await _apiConsumer.post(
      EndPoints.sessionInterfaceTransition(sessionId),
      body: params.toJson(),
    );
    return GlobalResponse<InterfaceTransitionModel>.fromJson(
      response.data as Map<String, dynamic>,
      withDataKey: false,
      fromJsonT: (json) =>
          InterfaceTransitionModel.fromJson(json['transition'] as Map<String, dynamic>? ?? const {}),
    );
  }

  @override
  Future<void> cancelInterfaceTransition(String sessionId) async {
    await _apiConsumer.delete(EndPoints.sessionInterfaceTransition(sessionId));
  }
}
```

- [ ] **Step 4: Run the data-source test to verify it passes**

Run: `flutter test test/feature/terminal/data/data_source/terminal_remote_data_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing repository test**

Create `packages/mobile/test/feature/terminal/data/repository/terminal_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

class _MockDataSource extends Mock implements TerminalRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

void main() {
  late _MockDataSource dataSource;
  late _MockNetworkStatus network;
  late TerminalRepositoryImp repository;

  const params = OpenSessionShellParams(projectId: 'p-1', sessionId: 's-1');

  setUpAll(() {
    registerFallbackValue(params);
    registerFallbackValue(const SendSessionMessageParams(message: ''));
  });

  setUp(() {
    dataSource = _MockDataSource();
    network = _MockNetworkStatus();
    repository = TerminalRepositoryImp(dataSource, network);
    when(() => network.isConnected).thenAnswer((_) async => true);
  });

  group('openSessionShell', () {
    // Back → Open shell must land on the same process, not leak a new PTY on
    // every visit, so an existing session-scoped handle wins.
    test('reuses the handle already open for this session', () async {
      when(() => dataSource.getShellTerminals()).thenAnswer(
        (_) async => const GlobalResponse(
          data: [
            ShellTerminalModel(handleId: 'other', sessionId: 's-other'),
            ShellTerminalModel(handleId: 'mine', sessionId: 's-1'),
          ],
        ),
      );

      final result = await repository.openSessionShell(params);

      expect(result.isSuccess, isTrue);
      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'mine');
      verifyNever(() => dataSource.openShellTerminal(any()));
    });

    test('opens a new shell when the session has none', () async {
      when(() => dataSource.getShellTerminals())
          .thenAnswer((_) async => const GlobalResponse(data: []));
      when(() => dataSource.openShellTerminal(any())).thenAnswer(
        (_) async => const GlobalResponse(data: ShellTerminalModel(handleId: 'fresh')),
      );

      final result = await repository.openSessionShell(params);

      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'fresh');
      verify(() => dataSource.openShellTerminal(params)).called(1);
    });

    test('opens a new shell when the list call fails rather than giving up', () async {
      when(() => dataSource.getShellTerminals())
          .thenThrow(ServerFailure(error: 'x', message: 'boom', statusCode: 500));
      when(() => dataSource.openShellTerminal(any())).thenAnswer(
        (_) async => const GlobalResponse(data: ShellTerminalModel(handleId: 'fresh')),
      );

      final result = await repository.openSessionShell(params);

      expect(result.getOrDefault(const GlobalResponse()).data?.handleId, 'fresh');
    });

    test('fails without touching the network when offline', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.openSessionShell(params);

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.getShellTerminals());
      verifyNever(() => dataSource.openShellTerminal(any()));
    });
  });

  group('sendSessionMessage', () {
    test('returns success when the daemon accepts it', () async {
      when(() => dataSource.sendSessionMessage(any(), any())).thenAnswer((_) async {});

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isSuccess, isTrue);
    });

    // The 409 code is the whole basis for rerouting to the PTY, so the failure
    // must arrive intact rather than flattened to a message.
    test('passes the daemon code through on failure', () async {
      when(() => dataSource.sendSessionMessage(any(), any())).thenThrow(
        ServerFailure(
          error: 'x',
          message: 'answer it in the session terminal first',
          statusCode: 409,
          apiStatus: 'SESSION_AWAITING_DECISION',
        ),
      );

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isFailure, isTrue);
      result.when(
        onSuccess: (_) => fail('expected a failure'),
        onFailure: (failure) => expect(failure.apiStatus, 'SESSION_AWAITING_DECISION'),
      );
    });

    test('fails offline without calling the data source', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.sendSessionMessage(
        's-1',
        const SendSessionMessageParams(message: 'go'),
      );

      expect(result.isFailure, isTrue);
      verifyNever(() => dataSource.sendSessionMessage(any(), any()));
    });
  });

  group('closeShellTerminal', () {
    test('returns success', () async {
      when(() => dataSource.closeShellTerminal(any())).thenAnswer((_) async {});

      expect((await repository.closeShellTerminal('h-1')).isSuccess, isTrue);
    });

    test('fails offline without calling the data source', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      expect((await repository.closeShellTerminal('h-1')).isFailure, isTrue);
      verifyNever(() => dataSource.closeShellTerminal(any()));
    });
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/feature/terminal/data/repository/terminal_repository_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 7: Write the repository**

Create `packages/mobile/lib/feature/terminal/data/repository/terminal_repository.dart`:

```dart
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/model/shell_terminal_model.dart';

abstract class TerminalRepository {
  FutureResult<GlobalResponse<ShellTerminalModel>> openSessionShell(OpenSessionShellParams params);
  FutureResult<bool> closeShellTerminal(String handleId);
  FutureResult<bool> sendSessionMessage(String sessionId, SendSessionMessageParams params);
  FutureResult<GlobalResponse<InterfaceTransitionStatusModel>> getInterfaceTransition(
    String sessionId,
  );
  FutureResult<GlobalResponse<InterfaceTransitionModel>> startInterfaceTransition(
    String sessionId,
    StartInterfaceTransitionParams params,
  );
  FutureResult<bool> cancelInterfaceTransition(String sessionId);
}

class TerminalRepositoryImp implements TerminalRepository {
  TerminalRepositoryImp(this._remoteDataSource, this._network);

  final TerminalRemoteDataSource _remoteDataSource;
  final NetworkStatus _network;

  @override
  FutureResult<GlobalResponse<ShellTerminalModel>> openSessionShell(
    OpenSessionShellParams params,
  ) => _guard(() async {
    final existing = await _existingShell(params.sessionId);
    if (existing != null) return GlobalResponse(data: existing);
    return _remoteDataSource.openShellTerminal(params);
  });

  /// A listing failure must not block opening a shell — the reuse is an
  /// optimisation, not a precondition.
  Future<ShellTerminalModel?> _existingShell(String sessionId) async {
    try {
      final listed = await _remoteDataSource.getShellTerminals();
      for (final shell in listed.data ?? const <ShellTerminalModel>[]) {
        if (shell.sessionId == sessionId) return shell;
      }
    } on Failure catch (_) {
      return null;
    }
    return null;
  }

  @override
  FutureResult<bool> closeShellTerminal(String handleId) =>
      _run(() => _remoteDataSource.closeShellTerminal(handleId));

  @override
  FutureResult<bool> sendSessionMessage(String sessionId, SendSessionMessageParams params) =>
      _run(() => _remoteDataSource.sendSessionMessage(sessionId, params));

  @override
  FutureResult<GlobalResponse<InterfaceTransitionStatusModel>> getInterfaceTransition(
    String sessionId,
  ) => _guard(() => _remoteDataSource.getInterfaceTransition(sessionId));

  @override
  FutureResult<GlobalResponse<InterfaceTransitionModel>> startInterfaceTransition(
    String sessionId,
    StartInterfaceTransitionParams params,
  ) => _guard(() => _remoteDataSource.startInterfaceTransition(sessionId, params));

  @override
  FutureResult<bool> cancelInterfaceTransition(String sessionId) =>
      _run(() => _remoteDataSource.cancelInterfaceTransition(sessionId));

  Future<Result<T, Failure>> _guard<T>(Future<T> Function() action) async {
    if (await _network.isConnected) {
      try {
        return Result.success(await action());
      } on Failure catch (error) {
        return Result.failure(error);
      }
    }
    return Result.failure(ServerFailure.noNetwork());
  }

  FutureResult<bool> _run(Future<void> Function() action) => _guard(() async {
    await action();
    return true;
  });
}
```

- [ ] **Step 8: Run the repository test to verify it passes**

Run: `flutter test test/feature/terminal/data/repository/terminal_repository_test.dart`
Expected: PASS.

- [ ] **Step 9: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 714/714 green.

```bash
git add packages/mobile/lib/feature/terminal/data packages/mobile/test/feature/terminal/data
git commit -m "feat(mobile): add the terminal data layer"
```

---

### Task 10: `TerminalCubit` — attaching the PTY

The port of `TerminalSessionScreen.tsx:699–834`. The cubit owns the `xterm.dart` `Terminal`, so PTY
bytes never depend on a widget being mounted.

One core change comes first: `MuxClient` publishes status as a broadcast stream with no replay, so a
cubit that subscribes *after* the board has already opened the socket would show "connecting..."
forever. The client gains a `currentStatus` field.

**Files:**
- Modify: `packages/mobile/lib/core/mux/mux_client.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_state.dart`
- Test: `packages/mobile/test/core/mux/mux_client_test.dart` (modify)
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_test.dart`

**Interfaces:**
- Consumes: `MuxClient` (`status`, `currentStatus`, `terminalEvents`, `openTerminal`, `sendInput`,
  `resize`, `closeTerminal`), `TerminalRepository`, `SessionsRepository`, `TerminalGrid`,
  `SendTarget`.
- Produces:
  - `class TerminalArgs extends Equatable {String id; String sessionId; String? projectId; String title; bool shellOnly;}`
  - `sealed class TerminalState`: `TerminalInitialState`, `TerminalReadyState(int revision)`,
    `TerminalClosedState`.
  - `TerminalCubit` with fields `terminal`, `composer`, `status`, `grid`, `authoritative`,
    `notFound`, `banner`, `restoring`, `sending`, `sendTarget`, `fontSize`, and methods
    `reportFit(TerminalGrid)`, `sendKey(String)`, `dismissBanner()` (Task 11 adds the rest).
  - On `MuxClient`: `MuxStatus get currentStatus`.

- [ ] **Step 1: Write the failing mux test**

Add to `packages/mobile/test/core/mux/mux_client_test.dart`, inside its existing `main()`:

```dart
  test('remembers the current status for late subscribers', () async {
    final socket = _FakeMuxSocket();
    final client = MuxClient(_config, connect: (_, _) => socket);

    expect(client.currentStatus, MuxStatus.closed);

    client.connect();
    await Future<void>.delayed(Duration.zero);

    expect(client.currentStatus, MuxStatus.open);

    await client.disconnect();
  });
```

Reuse the file's existing fake socket and config helpers; do not introduce new ones.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/mux/mux_client_test.dart`
Expected: FAIL — `currentStatus` is not defined.

- [ ] **Step 3: Publish the status on `MuxClient`**

In `packages/mobile/lib/core/mux/mux_client.dart`, replace every `_statusController.add(x)` call
with `_setStatus(x)` and add:

```dart
  MuxStatus _currentStatus = MuxStatus.closed;

  MuxStatus get currentStatus => _currentStatus;

  void _setStatus(MuxStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }
```

- [ ] **Step 4: Run the mux test to verify it passes**

Run: `flutter test test/core/mux/mux_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing cubit test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

void main() {
  late _MockMuxClient mux;
  late _MockTerminalRepository terminalRepository;
  late _MockSessionsRepository sessionsRepository;
  late StreamController<MuxStatus> statuses;
  late StreamController<TerminalEvent> events;

  const args = TerminalArgs(id: 's-1', sessionId: 's-1', projectId: 'p-1', title: 'Session');

  TerminalCubit build() => TerminalCubit(mux, terminalRepository, sessionsRepository, args);

  setUp(() {
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    sessionsRepository = _MockSessionsRepository();
    statuses = StreamController<MuxStatus>.broadcast();
    events = StreamController<TerminalEvent>.broadcast();
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
  });

  tearDown(() async {
    await statuses.close();
    await events.close();
  });

  test('attaches the PTY on construction and never touches the socket lifecycle', () async {
    final cubit = build();

    verify(() => mux.openTerminal('s-1', projectId: 'p-1')).called(1);
    verifyNever(() => mux.connect());
    expect(cubit.status, MuxStatus.open);

    await cubit.close();
    verify(() => mux.closeTerminal('s-1', projectId: 'p-1')).called(1);
    verifyNever(() => mux.disconnect());
  });

  test('writes PTY output into the terminal, across a split rune', () async {
    final cubit = build();
    final bytes = utf8.encode('héllo');

    events.add(TerminalDataEvent('s-1', Uint8List.fromList(bytes.sublist(0, 2))));
    events.add(TerminalDataEvent('s-1', Uint8List.fromList(bytes.sublist(2))));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.terminal.buffer.getText(), contains('héllo'));
    await cubit.close();
  });

  test('ignores output for another handle on the shared socket', () async {
    final cubit = build();

    events.add(TerminalDataEvent('other', Uint8List.fromList(utf8.encode('nope'))));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.terminal.buffer.getText(), isNot(contains('nope')));
    await cubit.close();
  });

  group('grid negotiation', () {
    test('reports the phone fit to the daemon and renders it until the daemon answers', () async {
      final cubit = build();

      cubit.reportFit(const TerminalGrid(40, 20));

      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(1);
      expect(cubit.grid, const TerminalGrid(40, 20));
      expect(cubit.authoritative, isFalse);
      await cubit.close();
    });

    test('does not re-send an unchanged fit', () async {
      final cubit = build();

      cubit.reportFit(const TerminalGrid(40, 20));
      cubit.reportFit(const TerminalGrid(40, 20));

      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(1);
      await cubit.close();
    });

    // The daemon's grid is authoritative: a co-viewing desktop owns the size and
    // the phone must mirror it rather than re-fitting and mis-drawing a TUI.
    test('adopts the daemon grid and stops rendering its own fit', () async {
      final cubit = build();
      cubit.reportFit(const TerminalGrid(40, 20));

      events.add(const TerminalResizeEvent('s-1', 120, 30));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.authoritative, isTrue);
      expect(cubit.grid, const TerminalGrid(120, 30));
      expect(cubit.terminal.viewWidth, 120);

      cubit.reportFit(const TerminalGrid(44, 22));
      expect(cubit.grid, const TerminalGrid(120, 30));
      verify(() => mux.resize('s-1', 44, 22, projectId: 'p-1')).called(1);
      await cubit.close();
    });
  });

  group('liveness', () {
    test('tracks the socket status', () async {
      final cubit = build();

      statuses.add(MuxStatus.closed);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.status, MuxStatus.closed);
      await cubit.close();
    });

    test('offers Restore rather than an error banner when the PTY is gone', () async {
      final cubit = build();

      events.add(const TerminalErrorEvent('s-1', 'Session not found'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, isNull);
      await cubit.close();
    });

    test('surfaces any other terminal error in the banner', () async {
      final cubit = build();

      events.add(const TerminalErrorEvent('s-1', 'pty write failed'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.banner, 'pty write failed');
      expect(cubit.notFound, isFalse);
      await cubit.close();
    });

    test('marks an exited session dead with its code', () async {
      final cubit = build();

      events.add(const TerminalExitedEvent('s-1', 130));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, 'Session exited (code 130)');
      await cubit.close();
    });
  });

  blocTest<TerminalCubit, TerminalState>(
    'sends a control sequence straight to the PTY',
    build: build,
    act: (cubit) => cubit.sendKey('\x03'),
    verify: (_) => verify(() => mux.sendInput('s-1', '\x03', projectId: 'p-1')).called(1),
  );
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 7: Write the state**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_state.dart`:

```dart
part of 'terminal_cubit.dart';

sealed class TerminalState extends Equatable {
  const TerminalState();

  @override
  List<Object?> get props => [];
}

final class TerminalInitialState extends TerminalState {
  const TerminalInitialState();
}

final class TerminalReadyState extends TerminalState {
  const TerminalReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}

final class TerminalClosedState extends TerminalState {
  const TerminalClosedState();
}
```

- [ ] **Step 8: Write the cubit (attach half)**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:xterm/xterm.dart';

part 'terminal_state.dart';

const double kTerminalMinFontSize = 7;
const double kTerminalMaxFontSize = 20;
const double kTerminalFontSize = 12;

class TerminalArgs extends Equatable {
  const TerminalArgs({
    required this.id,
    required this.sessionId,
    required this.title,
    this.projectId,
    this.shellOnly = false,
  });

  /// The PTY handle: an Operator session id, or a worktree shell's handleId.
  final String id;
  final String sessionId;
  final String title;
  final String? projectId;
  final bool shellOnly;

  @override
  List<Object?> get props => [id, sessionId, title, projectId, shellOnly];
}

class _TerminalWriteSink implements Sink<String> {
  _TerminalWriteSink(this._terminal);

  final Terminal _terminal;

  @override
  void add(String data) => _terminal.write(data);

  @override
  void close() {}
}

class TerminalCubit extends Cubit<TerminalState> {
  TerminalCubit(
    this._mux,
    this._repository,
    this._sessions,
    this.args, {
    Duration restoreDelay = const Duration(milliseconds: 1200),
  }) : _restoreDelay = restoreDelay,
       sendTarget = args.shellOnly ? SendTarget.terminal : SendTarget.agent,
       super(const TerminalInitialState()) {
    status = _mux.currentStatus;
    terminal.onOutput = (data) => _mux.sendInput(args.id, data, projectId: args.projectId);
    _statusSub = _mux.status.listen(_onStatus);
    _eventsSub = _mux.terminalEvents.where((event) => event.id == args.id).listen(_onEvent);
    _mux.openTerminal(args.id, projectId: args.projectId);
    _emit();
  }

  final MuxClient _mux;
  final TerminalRepository _repository;
  final SessionsRepository _sessions;
  final TerminalArgs args;
  final Duration _restoreDelay;

  final Terminal terminal = Terminal(maxLines: 5000);
  final TextEditingController composer = TextEditingController();

  MuxStatus status = MuxStatus.closed;
  TerminalGrid? grid;
  bool authoritative = false;
  bool notFound = false;
  bool restoring = false;
  bool sending = false;
  String? banner;
  SendTarget sendTarget;
  double fontSize = kTerminalFontSize;

  late final Sink<List<int>> _output = utf8.decoder
      .startChunkedConversion(_TerminalWriteSink(terminal));

  StreamSubscription<MuxStatus>? _statusSub;
  StreamSubscription<TerminalEvent>? _eventsSub;
  Timer? _reopenTimer;
  TerminalGrid? _lastFit;
  int _revision = 0;

  void _emit() => emit(TerminalReadyState(++_revision));

  void _onStatus(MuxStatus next) {
    status = next;
    _emit();
  }

  void _onEvent(TerminalEvent event) {
    switch (event) {
      case TerminalDataEvent(:final bytes):
        // Chunked so a multi-byte rune split across two frames still decodes.
        _output.add(bytes);
      case TerminalResizeEvent(:final cols, :final rows):
        authoritative = true;
        grid = TerminalGrid(cols, rows);
        terminal.resize(cols, rows);
        _emit();
      case TerminalExitedEvent(:final code):
        notFound = true;
        banner = 'Session exited (code $code)';
        _emit();
      case TerminalErrorEvent(:final message):
        // A missing PTY means the session is terminated — offer Restore instead
        // of surfacing it as a raw error banner.
        if (message.toLowerCase().contains('not found')) {
          notFound = true;
        } else {
          banner = message;
        }
        _emit();
      case TerminalOpenedEvent():
        break;
    }
  }

  /// The phone's natural grid. It is reported to the daemon so the PTY can be
  /// sized to the phone when the phone is the only viewer; it is only rendered
  /// while the daemon has not told us the authoritative size.
  void reportFit(TerminalGrid fit) {
    if (_lastFit == fit) return;
    _lastFit = fit;
    _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
    if (authoritative) return;
    grid = fit;
    terminal.resize(fit.cols, fit.rows);
    _emit();
  }

  void sendKey(String sequence) =>
      _mux.sendInput(args.id, sequence, projectId: args.projectId);

  void dismissBanner() {
    banner = null;
    _emit();
  }

  @override
  Future<void> close() {
    _reopenTimer?.cancel();
    unawaited(_statusSub?.cancel());
    unawaited(_eventsSub?.cancel());
    _mux.closeTerminal(args.id, projectId: args.projectId);
    composer.dispose();
    return super.close();
  }
}
```

- [ ] **Step 9: Run the cubit test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_test.dart`
Expected: PASS.

- [ ] **Step 10: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 726/726 green.

```bash
git add packages/mobile/lib/core/mux/mux_client.dart packages/mobile/lib/feature/terminal/presentation packages/mobile/test/core/mux/mux_client_test.dart packages/mobile/test/feature/terminal/presentation
git commit -m "feat(mobile): attach the PTY with TerminalCubit"
```

---

### Task 11: `TerminalCubit` — sending, killing, restoring, zooming

The port of `TerminalSessionScreen.tsx:865–903` (send + reroute), `1034–1081` (kill, close shell,
restore) and `1108–1112` (font zoom).

**Files:**
- Modify: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_actions_test.dart`

**Interfaces:**
- Consumes: everything Task 10 produced, plus `TerminalRepository.sendSessionMessage`,
  `TerminalRepository.closeShellTerminal`, `SessionsRepository.kill`, `SessionsRepository.restore`.
- Produces: on `TerminalCubit` — `Future<void> send()`, `void setSendTarget(SendTarget)`,
  `Future<void> terminate()`, `Future<void> restore()`, `void zoom(int delta)`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_actions_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class _MockMuxClient extends Mock implements MuxClient {}

class _MockTerminalRepository extends Mock implements TerminalRepository {}

class _MockSessionsRepository extends Mock implements SessionsRepository {}

void main() {
  late _MockMuxClient mux;
  late _MockTerminalRepository terminalRepository;
  late _MockSessionsRepository sessionsRepository;
  late StreamController<MuxStatus> statuses;
  late StreamController<TerminalEvent> events;

  const sessionArgs = TerminalArgs(
    id: 's-1',
    sessionId: 's-1',
    projectId: 'p-1',
    title: 'Session',
  );
  const shellArgs = TerminalArgs(
    id: 'h-1',
    sessionId: 's-1',
    projectId: 'p-1',
    title: 'Worktree shell',
    shellOnly: true,
  );

  TerminalCubit build([TerminalArgs args = sessionArgs]) => TerminalCubit(
    mux,
    terminalRepository,
    sessionsRepository,
    args,
    restoreDelay: const Duration(milliseconds: 10),
  );

  Failure awaitingDecision() => ServerFailure(
    error: 'x',
    message: 'answer it in the session terminal first',
    statusCode: 409,
    apiStatus: kAwaitingDecision,
  );

  setUpAll(() => registerFallbackValue(const SendSessionMessageParams(message: '')));

  setUp(() {
    mux = _MockMuxClient();
    terminalRepository = _MockTerminalRepository();
    sessionsRepository = _MockSessionsRepository();
    statuses = StreamController<MuxStatus>.broadcast();
    events = StreamController<TerminalEvent>.broadcast();
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
  });

  tearDown(() async {
    await statuses.close();
    await events.close();
  });

  group('send', () {
    test('sends to the agent route by default and clears the composer', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.success(true));
      final cubit = build();
      cubit.composer.text = 'ship it';

      await cubit.send();

      final captured = verify(
        () => terminalRepository.sendSessionMessage('s-1', captureAny()),
      ).captured.single as SendSessionMessageParams;
      expect(captured.message, 'ship it');
      expect(cubit.composer.text, isEmpty);
      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      await cubit.close();
    });

    test('writes to the PTY, with a submit, on the terminal route', () async {
      final cubit = build();
      cubit.setSendTarget(SendTarget.terminal);
      cubit.composer.text = 'yes,\nthe second one';

      await cubit.send();

      verify(() => mux.sendInput('s-1', 'yes, the second one\r', projectId: 'p-1')).called(1);
      expect(cubit.banner, kTerminalModeNotice);
      expect(cubit.composer.text, isEmpty);
      verifyNever(() => terminalRepository.sendSessionMessage(any(), any()));
      await cubit.close();
    });

    test('refuses the terminal route when the socket is not open, keeping the text', () async {
      when(() => mux.currentStatus).thenReturn(MuxStatus.closed);
      final cubit = build();
      cubit.setSendTarget(SendTarget.terminal);
      cubit.composer.text = 'y';

      await cubit.send();

      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      expect(cubit.banner, kTerminalUnavailableNotice);
      expect(cubit.composer.text, 'y');
      await cubit.close();
    });

    // The daemon refuses /send while the session is paused on a permission
    // prompt and says to answer in the terminal, so that is exactly what we do.
    test('reroutes to the PTY when the agent is blocked on a decision', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.failure(awaitingDecision()));
      final cubit = build();
      cubit.composer.text = 'approve';

      await cubit.send();

      verify(() => mux.sendInput('s-1', 'approve\r', projectId: 'p-1')).called(1);
      expect(cubit.sendTarget, SendTarget.terminal);
      expect(cubit.banner, kReroutedNotice);
      expect(cubit.composer.text, isEmpty);
      await cubit.close();
    });

    test('does not reroute onto a socket that is not open', () async {
      when(() => mux.currentStatus).thenReturn(MuxStatus.closed);
      when(() => terminalRepository.sendSessionMessage(any(), any()))
          .thenAnswer((_) async => Result.failure(awaitingDecision()));
      final cubit = build();
      cubit.composer.text = 'approve';

      await cubit.send();

      verifyNever(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId')));
      expect(cubit.banner, startsWith('Send failed:'));
      expect(cubit.composer.text, 'approve');
      await cubit.close();
    });

    test('keeps the text on any failure it did not handle', () async {
      when(() => terminalRepository.sendSessionMessage(any(), any())).thenAnswer(
        (_) async => Result.failure(
          ServerFailure(error: 'x', message: 'nope', statusCode: 500, apiStatus: 'INTERNAL'),
        ),
      );
      final cubit = build();
      cubit.composer.text = 'ship it';

      await cubit.send();

      expect(cubit.composer.text, 'ship it');
      expect(cubit.banner, 'Send failed: nope');
      await cubit.close();
    });

    test('ignores an empty composer', () async {
      final cubit = build();
      cubit.composer.text = '   ';

      await cubit.send();

      verifyNever(() => terminalRepository.sendSessionMessage(any(), any()));
      await cubit.close();
    });
  });

  group('terminate', () {
    test('kills the session and reports closed', () async {
      when(() => sessionsRepository.kill(any())).thenAnswer((_) async => Result.success(true));
      final cubit = build();

      await cubit.terminate();

      verify(() => sessionsRepository.kill('s-1')).called(1);
      expect(cubit.state, isA<TerminalClosedState>());
      await cubit.close();
    });

    test('closes the shell handle instead when this is a worktree shell', () async {
      when(() => terminalRepository.closeShellTerminal(any()))
          .thenAnswer((_) async => Result.success(true));
      final cubit = build(shellArgs);

      await cubit.terminate();

      verify(() => terminalRepository.closeShellTerminal('h-1')).called(1);
      verifyNever(() => sessionsRepository.kill(any()));
      expect(cubit.state, isA<TerminalClosedState>());
      await cubit.close();
    });

    test('stays on the screen with a banner when the kill fails', () async {
      when(() => sessionsRepository.kill(any())).thenAnswer(
        (_) async => Result.failure(ServerFailure(error: 'x', message: 'busy', statusCode: 409)),
      );
      final cubit = build();

      await cubit.terminate();

      expect(cubit.state, isA<TerminalReadyState>());
      expect(cubit.banner, 'Kill failed: busy');
      await cubit.close();
    });
  });

  group('restore', () {
    test('re-attaches the PTY after the daemon has had a moment to bring it up', () async {
      when(() => sessionsRepository.restore(any())).thenAnswer((_) async => Result.success(true));
      final cubit = build();
      cubit.reportFit(const TerminalGrid(40, 20));
      events.add(const TerminalErrorEvent('s-1', 'Session not found'));
      await Future<void>.delayed(Duration.zero);

      await cubit.restore();
      expect(cubit.notFound, isFalse);
      expect(cubit.restoring, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      verify(() => mux.openTerminal('s-1', projectId: 'p-1')).called(2);
      verify(() => mux.resize('s-1', 40, 20, projectId: 'p-1')).called(2);
      await cubit.close();
    });

    test('banners a failed restore and stays dead', () async {
      when(() => sessionsRepository.restore(any())).thenAnswer(
        (_) async =>
            Result.failure(ServerFailure(error: 'x', message: 'gone', statusCode: 409)),
      );
      final cubit = build();
      events.add(const TerminalExitedEvent('s-1', 1));
      await Future<void>.delayed(Duration.zero);

      await cubit.restore();

      expect(cubit.notFound, isTrue);
      expect(cubit.banner, 'Restore failed: gone');
      await cubit.close();
    });
  });

  group('zoom', () {
    test('steps the font size within its bounds', () async {
      final cubit = build();

      cubit.zoom(1);
      expect(cubit.fontSize, 13);

      for (var i = 0; i < 20; i++) {
        cubit.zoom(1);
      }
      expect(cubit.fontSize, kTerminalMaxFontSize);

      for (var i = 0; i < 40; i++) {
        cubit.zoom(-1);
      }
      expect(cubit.fontSize, kTerminalMinFontSize);
      await cubit.close();
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_actions_test.dart`
Expected: FAIL — `send`, `setSendTarget`, `terminate`, `restore`, `zoom` are not defined.

- [ ] **Step 3: Add the methods to the cubit**

In `terminal_cubit.dart`, add to `TerminalCubit`:

```dart
  void setSendTarget(SendTarget target) {
    sendTarget = target;
    _emit();
  }

  void zoom(int delta) {
    fontSize = (fontSize + delta).clamp(kTerminalMinFontSize, kTerminalMaxFontSize);
    _emit();
  }

  Future<void> send() async {
    final text = composer.text.trim();
    if (text.isEmpty) return;

    if (routeForSend(sendTarget) == SendTarget.terminal) {
      if (!_writeToPty(text)) {
        banner = kTerminalUnavailableNotice;
        _emit();
        return;
      }
      banner = kTerminalModeNotice;
      composer.clear();
      _emit();
      return;
    }

    sending = true;
    _emit();
    final result = await _repository.sendSessionMessage(
      args.sessionId,
      SendSessionMessageParams(message: text),
    );
    result.when(
      onSuccess: (_) => composer.clear(),
      onFailure: (failure) {
        // Only reroute onto a socket we actually hold open — otherwise the write
        // is a no-op and we would clear the field having sent nothing.
        if (routeForSend(sendTarget, failure) == SendTarget.terminal && _writeToPty(text)) {
          sendTarget = SendTarget.terminal;
          banner = kReroutedNotice;
          composer.clear();
          return;
        }
        banner = 'Send failed: ${failure.message}';
      },
    );
    sending = false;
    _emit();
  }

  bool _writeToPty(String text) {
    if (status != MuxStatus.open) return false;
    _mux.sendInput(args.id, terminalPayload(text), projectId: args.projectId);
    return true;
  }

  Future<void> terminate() async {
    final result = args.shellOnly
        ? await _repository.closeShellTerminal(args.id)
        : await _sessions.kill(args.sessionId);
    result.when(
      onSuccess: (_) => emit(const TerminalClosedState()),
      onFailure: (failure) {
        banner = '${args.shellOnly ? 'Close' : 'Kill'} failed: ${failure.message}';
        _emit();
      },
    );
  }

  Future<void> restore() async {
    restoring = true;
    _emit();
    final result = await _sessions.restore(args.sessionId);
    result.when(
      onSuccess: (_) {
        banner = null;
        notFound = false;
        _reopenTimer?.cancel();
        _reopenTimer = Timer(_restoreDelay, _reopen);
      },
      onFailure: (failure) => banner = 'Restore failed: ${failure.message}',
    );
    restoring = false;
    _emit();
  }

  /// The daemon needs a moment to bring the worktree agent's PTY back before the
  /// re-attach can land.
  void _reopen() {
    _mux.openTerminal(args.id, projectId: args.projectId);
    final fit = _lastFit;
    if (fit != null) _mux.resize(args.id, fit.cols, fit.rows, projectId: args.projectId);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/terminal_cubit_actions_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 740/740 green.

```bash
git add packages/mobile/lib/feature/terminal/presentation packages/mobile/test/feature/terminal/presentation
git commit -m "feat(mobile): add terminal sends, kill, restore and zoom"
```

---

### Task 12: `InterfaceSwitchCubit`

The port of `lib/session/useInterfaceTransition.ts:31–113`. One poller per session, shared by the
chat and terminal branches of the session route.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_state.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`

**Interfaces:**
- Consumes: `TerminalRepository.getInterfaceTransition/startInterfaceTransition/cancelInterfaceTransition`,
  the Task 7 predicates.
- Produces:
  - `sealed class InterfaceSwitchState`: `InterfaceSwitchInitialState`, `InterfaceSwitchReadyState(int revision)`.
  - `InterfaceSwitchCubit(TerminalRepository, String sessionId, {VoidCallback? onSettled, Duration activePoll, Duration idlePoll})`
    with fields `status`, `starting`, `cancelling`, `error`, getters `supported`, `reason`,
    `transition`, `active`, `cancellable`, `phase`, and methods `refresh()`,
    `start(String targetMode, String policy)`, `cancel()`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';

class _MockTerminalRepository extends Mock implements TerminalRepository {}

GlobalResponse<InterfaceTransitionStatusModel> _status({
  bool supported = true,
  String? phase,
  String? reason,
}) => GlobalResponse(
  data: InterfaceTransitionStatusModel(
    supported: supported,
    targetMode: 'chat',
    reason: reason,
    transition: phase == null
        ? null
        : InterfaceTransitionModel(id: 't-1', sessionId: 's-1', phase: phase),
  ),
);

void main() {
  late _MockTerminalRepository repository;

  setUpAll(() => registerFallbackValue(
        const StartInterfaceTransitionParams(targetMode: 'chat', policy: 'drain'),
      ));

  setUp(() => repository = _MockTerminalRepository());

  InterfaceSwitchCubit build({VoidCallback? onSettled}) => InterfaceSwitchCubit(
    repository,
    's-1',
    onSettled: onSettled,
    activePoll: const Duration(milliseconds: 5),
    idlePoll: const Duration(seconds: 30),
  );

  test('reads support and the current phase on construction', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.supported, isTrue);
    expect(cubit.phase, 'draining');
    expect(cubit.active, isTrue);
    expect(cubit.cancellable, isTrue);
    await cubit.close();
  });

  test('reports an unsupported session with the daemon\'s reason', () async {
    when(() => repository.getInterfaceTransition('s-1')).thenAnswer(
      (_) async => Result.success(_status(supported: false, reason: 'No chat driver.')),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.supported, isFalse);
    expect(cubit.reason, 'No chat driver.');
    expect(cubit.active, isFalse);
    await cubit.close();
  });

  test('surfaces a poll failure without dropping what it already knew', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));
    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    when(() => repository.getInterfaceTransition('s-1')).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'offline')),
    );
    await cubit.refresh();

    expect(cubit.error, 'offline');
    expect(cubit.phase, 'draining');
    await cubit.close();
  });

  test('fires onSettled exactly once when a transition finishes', () async {
    var settled = 0;
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'completed')));

    final cubit = build(onSettled: () => settled++);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.refresh();
    await cubit.refresh();

    expect(settled, 1);
    await cubit.close();
  });

  test('starts a transition and adopts the returned phase immediately', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status()));
    when(() => repository.startInterfaceTransition('s-1', any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(data: InterfaceTransitionModel(id: 't-1', phase: 'requested')),
      ),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.start('chat', 'interrupt');

    final captured = verify(
      () => repository.startInterfaceTransition('s-1', captureAny()),
    ).captured.last as StartInterfaceTransitionParams;
    expect(captured.policy, 'interrupt');
    expect(cubit.phase, 'requested');
    expect(cubit.starting, isFalse);
    await cubit.close();
  });

  test('keeps the terminal usable when starting fails', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status()));
    when(() => repository.startInterfaceTransition('s-1', any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'busy', statusCode: 409)),
    );

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.start('chat', 'drain');

    expect(cubit.error, 'busy');
    expect(cubit.active, isFalse);
    await cubit.close();
  });

  test('cancels and re-reads the status', () async {
    when(() => repository.getInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(_status(phase: 'draining')));
    when(() => repository.cancelInterfaceTransition('s-1'))
        .thenAnswer((_) async => Result.success(true));

    final cubit = build();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cubit.cancel();

    verify(() => repository.cancelInterfaceTransition('s-1')).called(1);
    expect(cubit.cancelling, isFalse);
    await cubit.close();
  });

  test('does not poll at all for a session-less shell', () async {
    final cubit = InterfaceSwitchCubit(repository, '', idlePoll: const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    verifyNever(() => repository.getInterfaceTransition(any()));
    expect(cubit.supported, isFalse);
    await cubit.close();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the state**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_state.dart`:

```dart
part of 'interface_switch_cubit.dart';

sealed class InterfaceSwitchState extends Equatable {
  const InterfaceSwitchState();

  @override
  List<Object?> get props => [];
}

final class InterfaceSwitchInitialState extends InterfaceSwitchState {
  const InterfaceSwitchInitialState();
}

final class InterfaceSwitchReadyState extends InterfaceSwitchState {
  const InterfaceSwitchReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
```

- [ ] **Step 4: Write the cubit**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_status_model.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/start_interface_transition_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';

part 'interface_switch_state.dart';

class InterfaceSwitchCubit extends Cubit<InterfaceSwitchState> {
  InterfaceSwitchCubit(
    this._repository,
    this.sessionId, {
    this.onSettled,
    Duration activePoll = const Duration(milliseconds: 300),
    Duration idlePoll = const Duration(seconds: 10),
  }) : _activePoll = activePoll,
       _idlePoll = idlePoll,
       super(const InterfaceSwitchInitialState()) {
    if (sessionId.isEmpty) return;
    unawaited(refresh());
    _schedule();
  }

  final TerminalRepository _repository;
  final String sessionId;
  final VoidCallback? onSettled;
  final Duration _activePoll;
  final Duration _idlePoll;

  InterfaceTransitionStatusModel? status;
  bool starting = false;
  bool cancelling = false;
  String? error;

  Timer? _timer;
  String _settledId = '';
  int _revision = 0;

  InterfaceTransitionModel? get transition => status?.transition;
  String? get phase => transition?.phase;
  bool get supported => status?.supported ?? false;
  String? get reason => status?.reason;
  bool get active => interfaceTransitionIsActive(phase);
  bool get cancellable => interfaceTransitionIsCancellable(phase);

  void _emit() => emit(InterfaceSwitchReadyState(++_revision));

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(active ? _activePoll : _idlePoll, () {
      unawaited(refresh().then((_) => _schedule()));
    });
  }

  Future<void> refresh() async {
    if (sessionId.isEmpty) return;
    final result = await _repository.getInterfaceTransition(sessionId);
    result.when(
      onSuccess: (response) {
        status = response.data;
        error = null;
        final settled = transition;
        if (settled != null &&
            !interfaceTransitionIsActive(settled.phase) &&
            _settledId != settled.id) {
          _settledId = settled.id ?? '';
          onSettled?.call();
        }
      },
      onFailure: (failure) => error = failure.message,
    );
    _emit();
  }

  Future<void> start(String targetMode, String policy) async {
    starting = true;
    error = null;
    _emit();
    final result = await _repository.startInterfaceTransition(
      sessionId,
      StartInterfaceTransitionParams(targetMode: targetMode, policy: policy),
    );
    result.when(
      onSuccess: (response) => status = InterfaceTransitionStatusModel(
        supported: status?.supported ?? true,
        targetMode: targetMode,
        reasonCode: status?.reasonCode,
        reason: status?.reason,
        transition: response.data,
      ),
      onFailure: (failure) => error = failure.message,
    );
    starting = false;
    _emit();
    _schedule();
  }

  Future<void> cancel() async {
    cancelling = true;
    error = null;
    _emit();
    final result = await _repository.cancelInterfaceTransition(sessionId);
    result.when(
      onSuccess: (_) {},
      onFailure: (failure) => error = failure.message,
    );
    cancelling = false;
    await refresh();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 748/748 green.

```bash
git add packages/mobile/lib/feature/terminal/presentation packages/mobile/test/feature/terminal/presentation
git commit -m "feat(mobile): add the Chat/Terminal interface switch cubit"
```

---
### Task 13: `TerminalSurface` — the renderer seam

The one widget that knows which renderer is in use. Everything above it talks to `TerminalCubit`,
so the documented fallback swaps this file and nothing else.

Gestures are wired through a `Listener`, which observes raw pointer events and **never enters the
gesture arena** — so `TerminalView`'s own one-finger scrolling (scrollback in the main buffer, wheel
or arrow-key synthesis in the alt buffer, `scroll_handler.dart:84–99`) keeps working, and this
widget only acts on two-finger pinches, on pans while zoomed, and on double taps.

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart`
- Create: `packages/mobile/test/feature/terminal/terminal_harness.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_surface_test.dart`

**Interfaces:**
- Consumes: `TerminalCubit` (`terminal`, `grid`, `fontSize`, `reportFit`), `measureCell`,
  `naturalFit`, `gridSize`, `fitScale`, `TerminalZoom` and friends, `TerminalPalette`.
- Produces:
  - `class TerminalSurface extends StatefulWidget` (no constructor arguments — it reads the cubit
    from the context).
  - The widget-test harness Tasks 14 and 15 also use: `TerminalHarness` with `mux`,
    `terminalRepository`, `sessionsRepository`, `switchCubit`, `events`, `statuses`, `cubit`,
    `start({bool shellOnly = false})`, `pump(WidgetTester, Widget)`, `dispose()`.

- [ ] **Step 1: Write the shared widget-test harness**

Three widget-test files need the same mocked mux, the same cubit and the same `SkinScope` wrapper.
Create `packages/mobile/test/feature/terminal/terminal_harness.dart` once:

```dart
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class MockMuxClient extends Mock implements MuxClient {}

class MockTerminalRepository extends Mock implements TerminalRepository {}

class MockSessionsRepository extends Mock implements SessionsRepository {}

class MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}

class TerminalHarness {
  final MockMuxClient mux = MockMuxClient();
  final MockTerminalRepository terminalRepository = MockTerminalRepository();
  final MockSessionsRepository sessionsRepository = MockSessionsRepository();
  final MockInterfaceSwitchCubit switchCubit = MockInterfaceSwitchCubit();
  final StreamController<MuxStatus> statuses = StreamController<MuxStatus>.broadcast();
  final StreamController<TerminalEvent> events = StreamController<TerminalEvent>.broadcast();

  late TerminalCubit cubit;

  void start({bool shellOnly = false}) {
    when(() => mux.status).thenAnswer((_) => statuses.stream);
    when(() => mux.terminalEvents).thenAnswer((_) => events.stream);
    when(() => mux.currentStatus).thenReturn(MuxStatus.open);
    when(() => mux.openTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.closeTerminal(any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.sendInput(any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => mux.resize(any(), any(), any(), projectId: any(named: 'projectId'))).thenReturn(null);
    when(() => switchCubit.state).thenReturn(const InterfaceSwitchInitialState());
    when(() => switchCubit.supported).thenReturn(true);
    when(() => switchCubit.reason).thenReturn(null);
    when(() => switchCubit.error).thenReturn(null);
    when(() => switchCubit.active).thenReturn(false);
    when(() => switchCubit.cancellable).thenReturn(false);
    when(() => switchCubit.cancelling).thenReturn(false);
    when(() => switchCubit.phase).thenReturn(null);
    when(() => switchCubit.start(any(), any())).thenAnswer((_) async {});
    when(() => switchCubit.cancel()).thenAnswer((_) async {});

    cubit = TerminalCubit(
      mux,
      terminalRepository,
      sessionsRepository,
      shellOnly
          ? const TerminalArgs(
              id: 'h-1',
              sessionId: 's-1',
              title: 'Worktree shell',
              shellOnly: true,
            )
          : const TerminalArgs(id: 's-1', sessionId: 's-1', title: 'Session'),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      SkinScope(
        skin: const DarkSkin(),
        child: MaterialApp(
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<TerminalCubit>.value(value: cubit),
                BlocProvider<InterfaceSwitchCubit>.value(value: switchCubit),
              ],
              child: SizedBox(width: 400, height: 600, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dispose() async {
    await cubit.close();
    await statuses.close();
    await events.close();
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_surface_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';
import 'package:xterm/xterm.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  Future<void> pumpSurface(WidgetTester tester) =>
      harness.pump(tester, const TerminalSurface());

  testWidgets('renders the terminal and reports the phone fit to the daemon', (tester) async {
    final cubit = harness.cubit;
    final mux = harness.mux;
    await pumpSurface(tester);

    expect(find.byType(TerminalView), findsOneWidget);
    expect(cubit.grid, isNotNull);
    expect(cubit.grid!.cols, greaterThan(1));
    expect(cubit.grid!.rows, greaterThan(1));
    verify(() => mux.resize('s-1', cubit.grid!.cols, cubit.grid!.rows, projectId: null)).called(1);
  });

  testWidgets('re-reports the fit after a zoom changes the cell size', (tester) async {
    final cubit = harness.cubit;
    await pumpSurface(tester);
    final before = cubit.grid!;

    cubit.zoom(-3);
    await tester.pump();

    expect(cubit.grid!.cols, greaterThan(before.cols));
  });

  testWidgets('renders the daemon grid rather than its own fit once told', (tester) async {
    final cubit = harness.cubit;
    await pumpSurface(tester);

    harness.events.add(const TerminalResizeEvent('s-1', 200, 50));
    await tester.pump();

    expect(cubit.grid, isNotNull);
    expect(cubit.grid!.cols, 200);
    expect(cubit.terminal.viewWidth, 200);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_surface_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 4: Write the widget**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/terminal_palette.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_zoom.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:xterm/xterm.dart';

const List<String> _monoFallback = ['Menlo', 'Courier New', 'monospace'];
const Duration _doubleTapWindow = Duration(milliseconds: 300);

class TerminalSurface extends StatefulWidget {
  const TerminalSurface({super.key});

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  final TerminalController _controller = TerminalController();
  final Map<int, Offset> _pointers = {};

  TerminalZoom _zoom = const TerminalZoom();
  TerminalZoom _pinchStart = const TerminalZoom();
  TerminalZoomBox _box = const TerminalZoomBox(content: Size.zero, view: Size.zero);
  double _minScale = 1;
  double _pinchDistance = 0;
  Offset _downAt = Offset.zero;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _distance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  Offset _focal() {
    final points = _pointers.values.toList();
    return (points[0] + points[1]) / 2;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _downAt = event.localPosition;
    if (_pointers.length == 2) {
      _pinchStart = _zoom;
      _pinchDistance = max(1, _distance());
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      setState(() {
        _zoom = scaleAround(
          _pinchStart,
          scale: _pinchStart.scale * (_distance() / _pinchDistance),
          focal: _focal(),
          box: _box,
          minScale: _minScale,
        );
      });
      return;
    }

    // At the overview the grid already fits, so a one-finger drag belongs to the
    // terminal's own scrolling and this handler stays out of the way.
    if (!_zoom.isZoomed(_minScale)) return;
    setState(() => _zoom = panBy(_zoom, event.localDelta, _box, _minScale));
  }

  void _onPointerUp(PointerUpEvent event) {
    final wasPinching = _pointers.length >= 2;
    _pointers.remove(event.pointer);
    if (wasPinching) return;

    final moved = (event.localPosition - _downAt).distance;
    final now = DateTime.now();
    if (moved <= 10 && now.difference(_lastTap) < _doubleTapWindow) {
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      setState(() {
        _zoom = toggleZoom(
          _zoom,
          focal: event.localPosition,
          box: _box,
          minScale: _minScale,
        );
      });
      return;
    }
    if (moved <= 10) _lastTap = now;
  }

  void _onPointerCancel(PointerCancelEvent event) => _pointers.remove(event.pointer);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    final skin = context.skin;

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, state) {
        final style = TerminalStyle(
          fontSize: cubit.fontSize,
          fontFamilyFallback: _monoFallback,
        );
        final cell = measureCell(style.toTextStyle());

        return LayoutBuilder(
          builder: (context, constraints) {
            final view = Size(constraints.maxWidth, constraints.maxHeight);
            final fit = naturalFit(view, cell);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) cubit.reportFit(fit);
            });

            final grid = cubit.grid ?? fit;
            final content = gridSize(grid, cell);
            final minScale = fitScale(grid, cell, view.width);
            if (minScale != _minScale) {
              _minScale = minScale;
              _zoom = TerminalZoom(scale: minScale);
            }
            _box = TerminalZoomBox(content: content, view: view);

            return ColoredBox(
              color: skin.bgBase,
              child: ClipRect(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    minHeight: 0,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform(
                      alignment: Alignment.topLeft,
                      transform: Matrix4.identity()
                        ..translate(_zoom.dx, _zoom.dy)
                        ..scale(_zoom.scale),
                      child: SizedBox(
                        width: content.width,
                        height: max(content.height, view.height),
                        child: TerminalView(
                          cubit.terminal,
                          controller: _controller,
                          theme: TerminalPalette.forBrightness(skin.themeMode == ThemeMode.light
                              ? Brightness.light
                              : Brightness.dark),
                          textStyle: style,
                          autoResize: false,
                          // The composer and key row own all input; the terminal
                          // must never raise a keyboard of its own.
                          readOnly: true,
                          hardwareKeyboardOnly: true,
                          backgroundOpacity: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_surface_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 751/751 green.

```bash
git add packages/mobile/lib/feature/terminal/presentation packages/mobile/test/feature/terminal
git commit -m "feat(mobile): render the PTY with xterm.dart"
```

---

### Task 14: The status bar, the key row and the composer

Ports `TerminalSessionScreen.tsx:1147–1200` (status bar), `lib/session/KeyRow.tsx` and
`lib/session/Composer.tsx` (with the mic slot absent, per the omissions table).

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_dock_test.dart`

**Interfaces:**
- Consumes: `TerminalCubit`, `kControlKeys`, `SendTarget`, `AppText`, `AppTextStyle`, `context.skin`.
- Produces: `TerminalStatusBar({required VoidCallback onKill, required VoidCallback onRestore})`,
  `TerminalKeyRow()`, `TerminalComposer()`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_dock_test.dart`,
built on the Task 13 harness:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/send_session_message_params.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/logic/terminal_fit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart';

import '../../../terminal_harness.dart';

void main() {
  late TerminalHarness harness;

  setUpAll(() => registerFallbackValue(const SendSessionMessageParams(message: '')));

  setUp(() => harness = TerminalHarness()..start());

  tearDown(() => harness.dispose());

  testWidgets('every control key writes its sequence to the PTY', (tester) async {
    await harness.pump(tester, const TerminalKeyRow());

    for (final key in kControlKeys) {
      await tester.tap(find.text(key.label));
      await tester.pump();
      verify(() => harness.mux.sendInput('s-1', key.sequence, projectId: null)).called(1);
    }
  });

  testWidgets('the composer sends and clears', (tester) async {
    final cubit = harness.cubit;
    when(() => harness.terminalRepository.sendSessionMessage(any(), any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalComposer());

    await tester.enterText(find.byType(TextField), 'ship it');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();

    expect(cubit.composer.text, isEmpty);
  });

  testWidgets('the route toggle switches the composer to the PTY', (tester) async {
    final cubit = harness.cubit;
    await harness.pump(tester, const TerminalComposer());

    await tester.tap(find.byTooltip('Switch to terminal'));
    await tester.pump();

    expect(cubit.sendTarget, SendTarget.terminal);
    expect(find.text('Send to terminal...'), findsOneWidget);
  });

  testWidgets('a plain worktree shell hides the misleading agent toggle', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalComposer());

    expect(find.byTooltip('Switch to terminal'), findsNothing);
    expect(find.byTooltip('Switch to chat'), findsNothing);
  });

  testWidgets('the status bar shows liveness, the grid and the zoom pair', (tester) async {
    final cubit = harness.cubit;
    await harness.pump(tester, TerminalStatusBar(onKill: () {}, onRestore: () {}));
    cubit.reportFit(const TerminalGrid(80, 24));
    await tester.pump();

    expect(find.text('live'), findsOneWidget);
    expect(find.text('80x24'), findsOneWidget);

    await tester.tap(find.byTooltip('Smaller text'));
    await tester.pump();
    expect(cubit.fontSize, 11);
  });

  testWidgets('the status bar offers Restore instead of Kill once the PTY is gone', (tester) async {
    var restored = 0;
    await harness.pump(tester, TerminalStatusBar(onKill: () {}, onRestore: () => restored++));

    harness.events.add(const TerminalExitedEvent('s-1', 1));
    await tester.pump();

    expect(find.bySemanticsLabel('Kill session'), findsNothing);
    await tester.tap(find.text('Restore'));
    expect(restored, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_dock_test.dart`
Expected: FAIL — the widget URIs do not exist.

- [ ] **Step 3: Write the key row**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/logic/keys.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

/// Fixed count, fixed height, one flex each: the row is pixel-identical in every
/// state the screen can reach.
class TerminalKeyRow extends StatelessWidget {
  const TerminalKeyRow({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        spacing: 5,
        children: [
          for (final key in kControlKeys)
            Expanded(
              child: Semantics(
                button: true,
                label: key.hint,
                child: InkWell(
                  onTap: () => cubit.sendKey(key.sequence),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border.all(color: skin.borderDefault),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: AppText(key.label, style: AppTextStyle.mono13Regular),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write the composer**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/terminal/logic/send_route.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalComposer extends StatelessWidget {
  const TerminalComposer({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, state) {
        final toTerminal = cubit.sendTarget == SendTarget.terminal;
        final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 7),
          child: Row(
            spacing: 7,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40, maxHeight: 108),
                  padding: const EdgeInsets.only(left: 11, right: 4),
                  decoration: BoxDecoration(
                    color: skin.bgElevated,
                    border: Border.all(color: skin.borderDefault),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cubit.composer,
                          maxLines: null,
                          style: AppTextStyle.style15Regular.copyWith(color: skin.textPrimary),
                          cursorColor: skin.blue,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            hintText: toTerminal ? 'Send to terminal...' : 'Message the agent...',
                            hintStyle: AppTextStyle.style15Regular.copyWith(color: skin.textFaint),
                          ),
                        ),
                      ),
                      if (!cubit.args.shellOnly)
                        IconButton(
                          tooltip: toTerminal ? 'Switch to chat' : 'Switch to terminal',
                          onPressed: () => cubit.setSendTarget(
                            toTerminal ? SendTarget.agent : SendTarget.terminal,
                          ),
                          icon: Icon(
                            toTerminal ? Icons.chat_bubble_outline : Icons.terminal,
                            size: 15,
                            color: toTerminal ? skin.textTertiary : skin.blue,
                          ),
                        ),
                      if (keyboardUp)
                        IconButton(
                          tooltip: 'Hide keyboard',
                          onPressed: () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
                          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: skin.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Send',
                child: InkWell(
                  onTap: cubit.sending ? null : cubit.send,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.send, size: 17, color: skin.onAccent),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

The composer is deliberately not auto-focused: the dock is always mounted, so focusing on mount
would pop the keyboard over the terminal every time the screen opens.

- [ ] **Step 5: Write the status bar**

Create `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalStatusBar extends StatelessWidget {
  const TerminalStatusBar({super.key, required this.onKill, required this.onRestore});

  final VoidCallback onKill;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<TerminalCubit>();

    return BlocBuilder<TerminalCubit, TerminalState>(
      buildWhen: (previous, current) => current is TerminalReadyState,
      builder: (context, state) {
        final grid = cubit.grid;
        final dead = cubit.notFound;
        final label = switch (cubit.status) {
          MuxStatus.connecting => 'connecting...',
          MuxStatus.open => 'live',
          MuxStatus.closed => 'disconnected',
          MuxStatus.error => 'error',
        };
        final color = switch (cubit.status) {
          MuxStatus.connecting => skin.attention,
          MuxStatus.open => skin.green,
          MuxStatus.closed => skin.textTertiary,
          MuxStatus.error => skin.red,
        };

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: skin.borderSubtle)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: AppText(
                  label,
                  style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                ),
              ),
              if (grid != null && !dead)
                AppText(
                  '${grid.cols}x${grid.rows}',
                  style: AppTextStyle.mono11Regular.copyWith(color: skin.textTertiary),
                ),
              if (!dead)
                Container(
                  margin: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: skin.bgElevated,
                    border: Border.all(color: skin.borderDefault),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Smaller text',
                        onPressed: () => cubit.zoom(-1),
                        icon: Icon(Icons.remove, size: 13, color: skin.textSecondary),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                        padding: EdgeInsets.zero,
                      ),
                      Container(width: 1, height: 24, color: skin.borderDefault),
                      IconButton(
                        tooltip: 'Larger text',
                        onPressed: () => cubit.zoom(1),
                        icon: Icon(Icons.add, size: 13, color: skin.textSecondary),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              if (dead && !cubit.args.shellOnly)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: InkWell(
                    onTap: cubit.restoring ? null : onRestore,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: skin.tintBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          Icon(Icons.restart_alt, size: 12, color: skin.blue),
                          AppText(
                            cubit.restoring ? 'Restoring...' : 'Restore',
                            style: AppTextStyle.style12Bold.copyWith(color: skin.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Semantics(
                    button: true,
                    label: cubit.args.shellOnly ? 'Close shell' : 'Kill session',
                    child: InkWell(
                      onTap: onKill,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: skin.tintRed,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          cubit.args.shellOnly ? Icons.close : Icons.delete_outline,
                          size: 14,
                          color: skin.red,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_dock_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 757/757 green.

```bash
git add packages/mobile/lib/feature/terminal/presentation packages/mobile/test/feature/terminal/presentation
git commit -m "feat(mobile): add the terminal status bar and input dock"
```

---

### Task 15: The terminal screen

Assembles the screen and its two overlays, and ports the three-way handoff prompt
(`TerminalSessionScreen.tsx:964–989`, `1145–1338`).

**Files:**
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/terminal_screen.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart`
- Create: `packages/mobile/lib/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart`
- Test: `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`

**Interfaces:**
- Consumes: `TerminalCubit`, `InterfaceSwitchCubit`, `dockInset` (`feature/chat/logic/keyboard_inset.dart`,
  where the spec's ledger placed it), `AppScaffold`, `GlobalAppbar`, `AppDialog`, `AppEmptyState`,
  `PrimaryButton`, `context.showSnackBar`.
- Produces:
  - `TerminalScreen()` — reads its arguments from `TerminalCubit.args`.
  - `TerminalBody()`, `TerminalDeadOverlay()`, `InterfaceSwitchOverlay()`.
  - `enum InterfaceSwitchChoice { drain, interrupt }` and
    `Future<InterfaceSwitchChoice?> showInterfaceSwitchSheet(BuildContext, {required String targetLabel, required bool busy, required bool waitingOnInput})`.

- [ ] **Step 1: Write the failing test**

Create `packages/mobile/test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`,
on the same harness (its `switchCubit` is already a `MockCubit<InterfaceSwitchState>`; override its
getters per test). `pumpScreen` is `harness.pump(tester, const TerminalScreen())`, and the
shell variant is `harness.dispose()` then `harness = TerminalHarness()..start(shellOnly: true)`:

```dart
  testWidgets('shows the terminal, its title and the dock', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    expect(find.text('Session'), findsOneWidget);
    expect(find.byType(TerminalSurface), findsOneWidget);
    expect(find.byType(TerminalKeyRow), findsOneWidget);
    expect(find.byType(TerminalComposer), findsOneWidget);
  });

  testWidgets('dismisses the banner when tapped', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    harness.events.add(const TerminalErrorEvent('s-1', 'pty write failed'));
    await tester.pump();
    expect(find.textContaining('pty write failed'), findsOneWidget);

    await tester.tap(find.textContaining('pty write failed'));
    await tester.pump();
    expect(find.textContaining('pty write failed'), findsNothing);
  });

  testWidgets('offers Restore over the dead terminal', (tester) async {
    when(() => harness.sessionsRepository.restore(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    harness.events.add(const TerminalExitedEvent('s-1', 1));
    await tester.pump();

    expect(find.text('Session terminated'), findsOneWidget);
    await tester.tap(find.text('Restore session'));
    await tester.pump();
    verify(() => harness.sessionsRepository.restore('s-1')).called(1);
  });

  testWidgets('confirms before killing, and leaves once the session is gone', (tester) async {
    when(() => harness.sessionsRepository.kill(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Kill session'));
    await tester.pumpAndSettle();
    expect(find.text('Kill session?'), findsOneWidget);

    await tester.tap(find.text('Kill'));
    await tester.pumpAndSettle();
    verify(() => harness.sessionsRepository.kill('s-1')).called(1);
  });

  testWidgets('a shell asks to close rather than kill', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    when(() => harness.terminalRepository.closeShellTerminal(any()))
        .thenAnswer((_) async => Result.success(true));
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Close shell'));
    await tester.pumpAndSettle();
    expect(find.text('Close shell?'), findsOneWidget);
  });

  testWidgets('explains why Chat is unavailable instead of starting a handoff', (tester) async {
    when(() => harness.switchCubit.supported).thenReturn(false);
    when(() => harness.switchCubit.reason).thenReturn('This agent has no chat driver.');
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Open Chat interface'));
    await tester.pumpAndSettle();

    expect(find.text('This agent has no chat driver.'), findsOneWidget);
    verifyNever(() => harness.switchCubit.start(any(), any()));
  });

  testWidgets('asks how to hand off, then starts the chosen policy', (tester) async {
    await harness.pump(tester, const TerminalScreen());

    await tester.tap(find.bySemanticsLabel('Open Chat interface'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish, then switch'));
    await tester.pumpAndSettle();

    verify(() => harness.switchCubit.start('chat', 'drain')).called(1);
  });

  testWidgets('covers the terminal while a transition is in flight', (tester) async {
    when(() => harness.switchCubit.active).thenReturn(true);
    when(() => harness.switchCubit.cancellable).thenReturn(true);
    when(() => harness.switchCubit.phase).thenReturn('draining');
    await harness.pump(tester, const TerminalScreen());

    expect(find.text('Switching to Chat'), findsOneWidget);
    expect(find.textContaining('Waiting for the current terminal turn'), findsOneWidget);

    await tester.tap(find.text('Cancel switch'));
    await tester.pump();
    verify(() => harness.switchCubit.cancel()).called(1);
  });

  testWidgets('a worktree shell has no Chat handoff at all', (tester) async {
    await harness.dispose();
    harness = TerminalHarness()..start(shellOnly: true);
    await harness.pump(tester, const TerminalScreen());

    expect(find.bySemanticsLabel('Open Chat interface'), findsNothing);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`
Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the dead overlay**

Create `…/widgets/terminal_dead_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class TerminalDeadOverlay extends StatelessWidget {
  const TerminalDeadOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;

    return ColoredBox(
      color: context.skin.bgBase,
      child: AppEmptyState(
        icon: Icons.power_settings_new,
        title: shellOnly ? 'Shell closed' : 'Session terminated',
        message: shellOnly
            ? 'This worktree shell is no longer running.'
            : 'This session has no live terminal. Restore it to bring the agent back.',
        action: shellOnly
            ? null
            : PrimaryButton(
                text: cubit.restoring ? 'Restoring...' : 'Restore session',
                onPressed: cubit.restoring ? null : cubit.restore,
              ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the switch overlay and sheet**

Create `…/widgets/interface_switch_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/terminal/logic/interface_transition.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';

class InterfaceSwitchOverlay extends StatelessWidget {
  const InterfaceSwitchOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<InterfaceSwitchCubit>();

    return ColoredBox(
      color: skin.scrim,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: skin.bgSurface,
            border: Border.all(color: skin.borderDefault),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, size: 22, color: skin.blue),
              const VerticalSpace(10),
              AppText('Switching to Chat', style: AppTextStyle.style16Bold),
              const VerticalSpace(10),
              AppText(
                interfaceTransitionLabel(cubit.phase),
                style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
                maxLines: 4,
                textAlign: TextAlign.center,
              ),
              if (cubit.cancellable) ...[
                const VerticalSpace(14),
                OutlinedButton(
                  onPressed: cubit.cancelling ? null : cubit.cancel,
                  child: AppText(
                    cubit.cancelling ? 'Cancelling…' : 'Cancel switch',
                    style: AppTextStyle.style12SemiBold,
                  ),
                ),
              ],
              if (cubit.error != null) ...[
                const VerticalSpace(10),
                AppText(
                  cubit.error!,
                  style: AppTextStyle.style11Regular.copyWith(color: skin.red),
                  maxLines: 3,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `…/widgets/interface_switch_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';

enum InterfaceSwitchChoice { drain, interrupt }

/// The agent is mid-turn, so the user must choose what happens to it. Three
/// options, which `AppDialog.confirm` cannot express.
Future<InterfaceSwitchChoice?> showInterfaceSwitchSheet(
  BuildContext context, {
  required String targetLabel,
  required bool waitingOnInput,
}) => showModalBottomSheet<InterfaceSwitchChoice>(
  context: context,
  backgroundColor: context.skin.bgSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
  ),
  builder: (sheetContext) {
    final skin = sheetContext.skin;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText('Switch to $targetLabel?', style: AppTextStyle.style16SemiBold),
            const VerticalSpace(8),
            AppText(
              waitingOnInput
                  ? 'This turn is waiting for your input. Finish waits for your answer; stop cancels it and switches now.'
                  : 'Keep the same Operator session, worktree, and native agent conversation.',
              style: AppTextStyle.style13Regular.copyWith(color: skin.textSecondary),
              maxLines: 4,
            ),
            const VerticalSpace(14),
            TextButton(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(InterfaceSwitchChoice.drain),
              child: AppText('Finish, then switch', style: AppTextStyle.style14SemiBold),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(InterfaceSwitchChoice.interrupt),
              child: AppText(
                'Stop and switch',
                style: AppTextStyle.style14SemiBold.copyWith(color: skin.red),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: AppText(
                'Keep Terminal UI',
                style: AppTextStyle.style14Medium.copyWith(color: skin.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
```

- [ ] **Step 5: Write the body**

Create `…/widgets/terminal_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/chat/logic/keyboard_inset.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_composer.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_dead_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_key_row.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_status_bar.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_surface.dart';

class TerminalBody extends StatelessWidget {
  const TerminalBody({super.key});

  Future<void> _confirmKill(BuildContext context) async {
    final cubit = context.read<TerminalCubit>();
    final shellOnly = cubit.args.shellOnly;
    final confirmed = await AppDialog.confirm(
      context,
      title: shellOnly ? 'Close shell?' : 'Kill session?',
      message: shellOnly
          ? 'This stops the worktree shell.'
          : 'This stops ${cubit.args.sessionId}.',
      confirmLabel: shellOnly ? 'Close' : 'Kill',
      destructive: true,
    );
    if (confirmed) await cubit.terminate();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: BlocBuilder<TerminalCubit, TerminalState>(
        buildWhen: (previous, current) => current is TerminalReadyState,
        builder: (context, state) {
          final cubit = context.read<TerminalCubit>();
          final banner = cubit.banner;

          return Column(
            children: [
              TerminalStatusBar(
                onKill: () => _confirmKill(context),
                onRestore: cubit.restore,
              ),
              if (banner != null)
                InkWell(
                  onTap: cubit.dismissBanner,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: skin.bgElevated,
                      border: Border(bottom: BorderSide(color: skin.borderDefault)),
                    ),
                    child: AppText(
                      '$banner (tap to dismiss)',
                      style: AppTextStyle.style12Regular.copyWith(color: skin.attention),
                      maxLines: 3,
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: TerminalSurface()),
                    if (cubit.notFound) const Positioned.fill(child: TerminalDeadOverlay()),
                    BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>(
                      buildWhen: (previous, current) => current is InterfaceSwitchReadyState,
                      builder: (context, _) =>
                          context.read<InterfaceSwitchCubit>().active
                          ? const Positioned.fill(child: InterfaceSwitchOverlay())
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.only(bottom: dockInset(keyboard, safeBottom)),
                decoration: BoxDecoration(
                  color: skin.bgSurface,
                  border: Border(top: BorderSide(color: skin.borderSubtle)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [TerminalKeyRow(), TerminalComposer()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Write the screen**

Create `…/ui/terminal_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_body.dart';

class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  Future<void> _requestSwitch(BuildContext context) async {
    final switchCubit = context.read<InterfaceSwitchCubit>();
    if (!switchCubit.supported) {
      context.showSnackBar(
        switchCubit.reason ??
            switchCubit.error ??
            'This agent has not declared a compatible native conversation handoff.',
      );
      return;
    }
    if (!context.read<TerminalCubit>().notFound) {
      final choice = await showInterfaceSwitchSheet(
        context,
        targetLabel: 'Chat',
        waitingOnInput: false,
      );
      if (choice == null) return;
      await switchCubit.start('chat', choice == InterfaceSwitchChoice.drain ? 'drain' : 'interrupt');
      return;
    }
    await switchCubit.start('chat', 'drain');
  }

  @override
  Widget build(BuildContext context) {
    final args = context.read<TerminalCubit>().args;
    final title = args.title.length > 22 ? '${args.title.substring(0, 20)}...' : args.title;

    return BlocListener<TerminalCubit, TerminalState>(
      listener: (context, state) {
        if (state is TerminalClosedState) Navigator.of(context).pop();
      },
      child: AppScaffold(
        appBar: GlobalAppbar.sub(
          titleText: title,
          actions: [
            if (!args.shellOnly)
              Semantics(
                button: true,
                label: 'Open Chat interface',
                child: IconButton(
                  onPressed: () => _requestSwitch(context),
                  icon: Icon(Icons.chat_bubble_outline, size: 18, color: context.skin.blue),
                ),
              ),
          ],
        ),
        body: const TerminalBody(),
      ),
    );
  }
}
```

The "drain straight away when the agent is idle" branch of RN's `requestInterfaceSwitch` needs the
board's view of the session's activity. `TerminalCubit` does not hold it, so the sheet is shown
whenever the terminal is live and the drain-only path is taken when the PTY is already gone — a
strictly safer default than guessing "idle" and interrupting a working agent. Record it in the
deviations table when this task lands.

- [ ] **Step 7: Run the test to verify it passes**

Run: `flutter test test/feature/terminal/presentation/terminal_screen/ui/terminal_screen_test.dart`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 766/766 green.

```bash
git add packages/mobile/lib/feature/terminal/presentation packages/mobile/test/feature/terminal/presentation
git commit -m "feat(mobile): assemble the terminal screen"
```

---

### Task 16: Routing and dependency injection

Puts the screen on the router, replaces the session route's placeholder, and registers the feature.

**Files:**
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart`
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart`
- Modify: `packages/mobile/lib/core/utils/service_locator.dart`
- Modify: `packages/mobile/lib/feature/sessions/presentation/session_route/ui/session_route_screen.dart`
- Test: `packages/mobile/test/core/app_routes/app_router_test.dart` (modify)
- Test: `packages/mobile/test/core/utils/service_locator_test.dart` (modify)
- Test: `packages/mobile/test/feature/sessions/presentation/session_route/session_route_screen_test.dart` (modify)

**Interfaces:**
- Consumes: `TerminalCubit`, `InterfaceSwitchCubit`, `TerminalArgs`, `TerminalRepository`.
- Produces: `RoutesStrings.terminal`, the `/terminal` route (arguments: `{'args': TerminalArgs}`),
  `InterfaceSwitchCubit` on the session route, `ServiceLocator._terminalFeatureSetup()`.

- [ ] **Step 1: Write the failing tests**

In `test/core/app_routes/app_router_test.dart`, add two mock classes beside the file's existing
`_MockSessionsCubit`:

```dart
class _MockTerminalCubit extends MockCubit<TerminalState> implements TerminalCubit {}

class _MockInterfaceSwitchCubit extends MockCubit<InterfaceSwitchState>
    implements InterfaceSwitchCubit {}
```

and the test:

```dart
  test('routes the terminal through a BlocProvider', () async {
    await sl.reset();
    sl.registerLazySingleton<SessionsCubit>(_MockSessionsCubit.new);
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>((_, _) => _MockTerminalCubit());
    sl.registerFactoryParam<InterfaceSwitchCubit, String, void>((_, _) => _MockInterfaceSwitchCubit());

    expect(
      builtWidgetFor(
        RoutesStrings.terminal,
        arguments: {
          'args': const TerminalArgs(id: 'h-1', sessionId: 's-1', title: 'Worktree shell', shellOnly: true),
        },
      ),
      isA<MultiBlocProvider>(),
    );

    await sl.reset();
  });
```

In `test/feature/sessions/presentation/session_route/session_route_screen_test.dart`, replace the
assertion that a `tui` session renders the placeholder with:

```dart
  testWidgets('renders the terminal for a tui session', (tester) async {
    await pumpRoute(tester, sessions: [const SessionModel(id: 's-1', mode: 'tui')]);

    expect(find.byType(TerminalScreen), findsOneWidget);
    expect(find.text('Terminal UI is not in this build yet'), findsNothing);
  });
```

In `test/core/utils/service_locator_test.dart`, extend the registration assertions with
`TerminalRepository`, `TerminalRemoteDataSource`, `TerminalCubit` and `InterfaceSwitchCubit`,
following the pattern the file already uses for the chat feature.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/app_routes/app_router_test.dart test/core/utils/service_locator_test.dart test/feature/sessions/presentation/session_route/session_route_screen_test.dart`
Expected: FAIL — `RoutesStrings.terminal` is not defined; the `tui` branch still renders the placeholder.

- [ ] **Step 3: Add the route constant and the route**

In `routes_strings.dart`:

```dart
  static const String terminal = '/terminal';
```

In `app_router.dart`, add the case:

```dart
      case RoutesStrings.terminal:
        final args = (settings.arguments as Map<String, dynamic>?)?['args'] as TerminalArgs?;
        final terminalArgs =
            args ?? const TerminalArgs(id: '', sessionId: '', title: 'Terminal');
        return MaterialPageRoute(
          builder: (context) => MultiBlocProvider(
            providers: [
              BlocProvider<TerminalCubit>(create: (_) => sl<TerminalCubit>(param1: terminalArgs)),
              BlocProvider<InterfaceSwitchCubit>(
                create: (_) => sl<InterfaceSwitchCubit>(param1: terminalArgs.shellOnly ? '' : terminalArgs.sessionId),
              ),
            ],
            child: const TerminalScreen(),
          ),
          settings: settings,
        );
```

and add `InterfaceSwitchCubit` to the existing `RoutesStrings.session` case's `MultiBlocProvider`,
so the chat branch and the terminal branch share one poller:

```dart
              BlocProvider<InterfaceSwitchCubit>(
                create: (_) => sl<InterfaceSwitchCubit>(param1: sessionId),
              ),
```

- [ ] **Step 4: Register the feature**

In `service_locator.dart`, add `import 'dart:async';` (for `unawaited`), add
`_terminalFeatureSetup();` to `init()`, and add:

```dart
  static void _terminalFeatureSetup() {
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>(
      (args, _) => TerminalCubit(
        sl<MuxClient>(),
        sl<TerminalRepository>(),
        sl<SessionsRepository>(),
        args,
      ),
    );
    sl.registerFactoryParam<InterfaceSwitchCubit, String, void>(
      (sessionId, _) => InterfaceSwitchCubit(
        sl<TerminalRepository>(),
        sessionId,
        onSettled: () => unawaited(sl<SessionsCubit>().refresh()),
      ),
    );

    sl.registerLazySingleton<TerminalRepository>(
      () => TerminalRepositoryImp(sl<TerminalRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<TerminalRemoteDataSource>(
      () => TerminalRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
```

`onSettled` refreshes the board so a completed handoff flips the session's mode and the session
route re-resolves to the other renderer — RN passes the board's `refresh` into the hook for exactly
this.

- [ ] **Step 5: Render the terminal from the session route**

In `session_route_screen.dart`, replace the `tui` placeholder branch:

```dart
        if (session?.mode == 'tui') {
          return BlocProvider<TerminalCubit>(
            create: (_) => sl<TerminalCubit>(
              param1: TerminalArgs(
                id: session!.id,
                sessionId: session.id,
                title: session.title,
                projectId: session.projectId,
              ),
            ),
            child: const TerminalScreen(),
          );
        }
```

`InterfaceSwitchCubit` is already above this widget, from the route. The remaining `Scaffold` with
`AppEmptyState` stays for the loading and not-found cases, and the `AppEmptyState` import stays with
it; delete only the "Terminal UI is not in this build yet" branch.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/core/app_routes/app_router_test.dart test/core/utils/service_locator_test.dart test/feature/sessions/presentation/session_route/session_route_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 768/768 green.

```bash
git add packages/mobile/lib/core packages/mobile/lib/feature/sessions packages/mobile/test/core packages/mobile/test/feature/sessions
git commit -m "feat(mobile): route tui sessions to the terminal screen"
```

---

### Task 17: The chat session's terminal doors

Restores the three entry points M3 deliberately omitted: the menu's worktree shell, the menu's
Terminal UI handoff, and the "Open shell" action on the stopped and unavailable states
(`ChatSessionScreen.tsx:91–101, 152, 291–292, 331`).

**Files:**
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/chat_body.dart`
- Modify: `packages/mobile/lib/feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart`
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart` (modify)
- Test: `packages/mobile/test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart` (modify)

**Interfaces:**
- Consumes: `TerminalRepository.openSessionShell`, `InterfaceSwitchCubit`, `RoutesStrings.terminal`,
  `TerminalArgs`, `showInterfaceSwitchSheet`.
- Produces: `ConversationMenuAction.worktreeShell`, `ConversationMenuAction.terminalUi`, and a
  `VoidCallback? onOpenShell` on `ConversationBanners`.

- [ ] **Step 1: Write the failing tests**

In `chat_sheets_test.dart`, add to the conversation-menu group:

```dart
  testWidgets('offers the worktree shell and the Terminal UI handoff', (tester) async {
    await pumpMenu(tester);

    expect(find.text('Open worktree shell'), findsOneWidget);
    expect(find.text('Open Terminal UI'), findsOneWidget);

    await tester.tap(find.text('Open worktree shell'));
    await tester.pumpAndSettle();
    expect(result?.action, ConversationMenuAction.worktreeShell);
  });
```

In `chat_body_test.dart`, add:

```dart
  testWidgets('opens a worktree shell and pushes the terminal route', (tester) async {
    when(() => terminalRepository.openSessionShell(any())).thenAnswer(
      (_) async => Result.success(
        const GlobalResponse(data: ShellTerminalModel(handleId: 'h-1', title: 'Worktree shell')),
      ),
    );
    await pumpChatBody(tester);

    await openMenuAndTap(tester, 'Open worktree shell');

    final captured = verify(() => terminalRepository.openSessionShell(captureAny()))
        .captured
        .single as OpenSessionShellParams;
    expect(captured.sessionId, 's-1');
    expect(pushedRoutes, contains(RoutesStrings.terminal));
  });

  testWidgets('reports why a shell could not be opened instead of failing silently', (tester) async {
    when(() => terminalRepository.openSessionShell(any())).thenAnswer(
      (_) async => Result.failure(ServerFailure(error: 'x', message: 'no worktree')),
    );
    await pumpChatBody(tester);

    await openMenuAndTap(tester, 'Open worktree shell');
    await tester.pump();

    expect(find.text('Could not open shell: no worktree'), findsOneWidget);
  });

  testWidgets('asks how to hand off before switching to the Terminal UI', (tester) async {
    when(() => switchCubit.supported).thenReturn(true);
    await pumpChatBody(tester);

    await openMenuAndTap(tester, 'Open Terminal UI');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop and switch'));
    await tester.pumpAndSettle();

    verify(() => switchCubit.start('tui', 'interrupt')).called(1);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`
Expected: FAIL — the rows do not exist.

- [ ] **Step 3: Add the menu rows**

In `conversation_menu_sheet.dart`, extend the enum with `worktreeShell` and `terminalUi`, add the
`openingShell` and `interfaceSupported` flags to `showConversationMenuSheet` and the sheet, and add
the two rows directly after the "Conversation map" row:

```dart
          _MenuRow(
            icon: Icons.terminal,
            label: widget.openingShell ? 'Opening shell…' : 'Open worktree shell',
            hint: 'A plain terminal in this session\'s worktree',
            enabled: !widget.openingShell,
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.worktreeShell),
            ),
          ),
          _MenuRow(
            icon: Icons.swap_horiz,
            label: 'Open Terminal UI',
            hint: widget.interfaceSupported
                ? 'Keep the session, worktree and conversation; drive the agent\'s own TUI'
                : 'This agent has not declared a compatible handoff',
            enabled: widget.interfaceSupported,
            onTap: () => Navigator.of(context).pop(
              const ConversationMenuResult(ConversationMenuAction.terminalUi),
            ),
          ),
```

- [ ] **Step 4: Handle the actions**

`Result.when` is an extension method, so any file that calls it must import
`core/helpers/result/result.dart` directly — a transitive import through a repository does not bring
it into scope. `chat_body.dart` does not import it yet; add
`import 'package:operator_mobile/core/helpers/result/result.dart';` alongside the new
`OpenSessionShellParams`, `TerminalArgs`, `TerminalRepository`, `RoutesStrings`,
`InterfaceSwitchCubit` and `showInterfaceSwitchSheet` imports.

In `chat_body.dart`, pass `openingShell: _openingShell` and
`interfaceSupported: context.read<InterfaceSwitchCubit>().supported` into
`showConversationMenuSheet`, add the two `switch` arms, and add the shell opener:

```dart
      case ConversationMenuAction.worktreeShell:
        await _openShell();
      case ConversationMenuAction.terminalUi:
        await _switchToTerminal();
```

```dart
  bool _openingShell = false;

  Future<void> _openShell() async {
    final projectId = widget.projectId;
    final sessionId = context.read<ChatCubit>().sessionId;
    if (projectId == null) {
      context.showSnackBar('This session has no project, so it has no worktree shell.');
      return;
    }
    if (_openingShell) return;
    setState(() => _openingShell = true);
    final result = await sl<TerminalRepository>().openSessionShell(
      OpenSessionShellParams(projectId: projectId, sessionId: sessionId),
    );
    if (!mounted) return;
    setState(() => _openingShell = false);
    result.when(
      onSuccess: (response) {
        final shell = response.data;
        final handleId = shell?.handleId;
        if (handleId == null) {
          context.showSnackBar('Could not open shell: the daemon returned no handle.');
          return;
        }
        Navigator.of(context).pushNamed(
          RoutesStrings.terminal,
          arguments: {
            'args': TerminalArgs(
              id: handleId,
              sessionId: sessionId,
              projectId: projectId,
              title: shell?.title ?? 'Worktree shell',
              shellOnly: true,
            ),
          },
        );
      },
      onFailure: (failure) => context.showSnackBar('Could not open shell: ${failure.message}'),
    );
  }

  Future<void> _switchToTerminal() async {
    final switchCubit = context.read<InterfaceSwitchCubit>();
    if (!switchCubit.supported) {
      context.showSnackBar(
        switchCubit.reason ?? 'This agent has not declared a compatible native conversation handoff.',
      );
      return;
    }
    final choice = await showInterfaceSwitchSheet(
      context,
      targetLabel: 'Terminal UI',
      waitingOnInput: context.read<ChatCubit>().snapshot?.hasTurnInFlight ?? false,
    );
    if (choice == null || !mounted) return;
    await switchCubit.start('tui', choice == InterfaceSwitchChoice.drain ? 'drain' : 'interrupt');
  }
```

- [ ] **Step 5: Give the banners their shell action back**

In `conversation_banners.dart`, add `this.onOpenShell` to the constructor and field list, and add
`secondary: 'Shell'` / `onSecondary: onOpenShell` to the `controllerState == 'stopped'` banner and
to the reauth banner (`InlineBanner` already supports both, `inline_banner.dart:24–27`). Pass
`onOpenShell: _openShell` from `chat_body.dart`, and add the same action to the "Conversation
unavailable" empty state:

```dart
            action: PrimaryButton(
              text: _openingShell ? 'Opening…' : 'Open worktree shell',
              onPressed: _openingShell ? null : _openShell,
            ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/feature/chat/presentation/chat_screen/ui/chat_sheets_test.dart test/feature/chat/presentation/chat_screen/ui/chat_body_test.dart`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: "No issues found!", 773/773 green.

```bash
git add packages/mobile/lib/feature/chat packages/mobile/test/feature/chat
git commit -m "feat(mobile): open the worktree shell and Terminal UI from chat"
```

---

## Milestone verification

M4 is done when, from `packages/mobile`:

- `flutter analyze` → "No issues found!"
- `flutter test` → 773/773 green
- On a real phone against a real daemon:
  - tapping a `tui`-mode session on the Agents tab opens its terminal, and output streams live;
  - the status bar shows `live` and the grid, and the ± pair changes the font size and the grid with it;
  - the composer sends to the agent; flipping the toggle sends to the PTY with a submit; answering a
    permission prompt while the agent is paused reroutes to the PTY and says so;
  - the eight control keys reach the PTY (`^C` interrupts a running command);
  - one finger scrolls, two fingers pinch, a double tap toggles overview ↔ 1:1;
  - Kill asks first and returns to the board; a terminated session offers Restore, and restoring
    re-attaches the PTY;
  - the chat menu's "Open worktree shell" opens a shell, and returning and re-opening lands on the
    same shell rather than a new one;
  - the chat menu's "Open Terminal UI" hands a chat session over, the scrim explains each phase, and
    the board flips the session's mode when it settles.

## Spike outcome

*(Filled in by Task 1, before Task 2 starts.)*

| Criterion | Verdict | Evidence |
|---|---|---|
| 1 · Gesture parity | PASS | Two-finger pinch visibly scales the grid (`Transform.scale` responds to a `Listener`-tracked pinch, confirmed shrinking on screen); one-finger drag scrolls without the pinch recognizer interfering — for a plain shell it drives `TerminalView`'s own `scrollController`, for an alt-buffer TUI (Claude Code itself, confirmed via `terminal.isUsingAltBuffer == true`) it forwards arrow-key input, which the app visibly acknowledged (`History 1/3`, its own `Up / Scroll wheel` hint). A `GestureDetector(onScaleStart/onScaleUpdate)` was tried first and reproduced the arena conflict this table's row 4 warns about; switching to a `Listener` (Task 13's actual design) resolved it. |
| 2 · PTY fit negotiation | PASS | The AppBar's grid readout changed from the phone's own negotiated size to `daemon 109 x 38` once the daemon echoed back a size — the reported grid reaches the daemon and the daemon's authoritative size is reflected back. |
| 3 · Output bursts | PROVISIONAL PASS | iOS Simulator does not support `--release` or `--profile` builds (`flutter run` errors on both), so this only ran in debug/JIT mode against a session that had already printed 3000 lines — no dropped frames or freeze observed, but a debug build's frame times are not the evidence the plan calls for. Needs a real-device or `flutter build` re-check before trusting it under load. |
| 4 · Selection and copy | PASS, with a caveat | Programmatic selection (`TerminalController.setSelection` with buffer anchors, bypassing the gesture layer) rendered a visible highlight and `_copy()` put the exact selected text on the clipboard (verified via `xcrun simctl pbpaste booted`) — the renderer's selection/copy pipeline is correct. Synthetic long-press through the simulator-automation tool used to drive this session could not be made to reliably trigger xterm's `LongPressGestureRecognizer` (`onLongPressStart` never fired on repeated attempts, both before and after switching from `GestureDetector` to `Listener`), so real-device/manual confirmation of the touch trigger itself is still outstanding. |

## Ledger rows closed here

| Spec ledger row | Landed as | Note |
|---|---|---|
| `session/sendRoute.test.ts` | `test/feature/terminal/logic/send_route_test.dart` (Task 4) | Path differs from the spec's `test/feature/sessions/logic/…`; the module's only consumer is the terminal feature. |
| `session/keyboardInset.test.ts` (`CONTROL_KEYS` half) | `test/feature/terminal/logic/keys_test.dart` (Task 3) | The `dockInset` half landed in M3 at `test/feature/chat/logic/keyboard_inset_test.dart`. Together the row is complete. |
| `theme.test.ts` (terminal palette half) | `test/core/app_themes/terminal_palette_test.dart` (Task 2) | The skin half landed in M0 at `test/core/app_themes/skin_test.dart`. |

Nothing else in the spec's 37-row ledger belongs to M4. The tests added by Tasks 5–17
(`terminal_fit`, `terminal_zoom`, `interface_transition`, the data layer, both cubits and the
widgets) have no RN counterpart — they cover Dart-side behavior that RN implemented in injected
JavaScript or in React hooks.

## What M4 leaves for later milestones

| Left open | Milestone |
|---|---|
| The preview globe, its poll and the in-app browser overlay | M5 |
| The composer's mic and the voice strip | M5 |
| Deep-linking to `/terminal` from a push notification | M5 |
| Haptics on keys, sends, kill and restore | M6 parity sweep |
| Deleting `packages/mobile_rn` | M6 |
