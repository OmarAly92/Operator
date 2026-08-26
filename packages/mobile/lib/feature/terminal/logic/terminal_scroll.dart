import 'package:xterm/xterm.dart';

/// tmux scrolls five lines for every wheel event it acts on:
///
///     bind-key -T copy-mode WheelUpPane select-pane \; send-keys -X -N 5 scroll-up
///
/// xterm.dart raises one wheel event per line of finger travel, so reporting
/// every one of them scrolls five times as far as the drag. Dividing by this
/// step puts the content back under the finger.
const int kTmuxWheelLines = 5;

const String _pageUp = '\x1b[5~';
const String _pageDown = '\x1b[6~';

/// SGR wheel buttons. The 64 bit already marks the report as a wheel event and
/// the low bits pick the direction, so up is 64 and down is 65. Adding the X10
/// wheel button numbers (4 and 5) on top overflows into the modifier bits and
/// reports Shift+wheel, which tmux leaves unbound and silently ignores.
const int _sgrWheelUp = 64;
const int _sgrWheelDown = 65;

/// What a scroll gesture should do for the pane currently on screen. Mirrors
/// the desktop renderer's wheel routing (XtermTerminal.tsx) so the two clients
/// scroll the same pane the same way.
enum TerminalScrollAction {
  /// Report the wheel to the pane; tmux turns it into a copy-mode scroll.
  mouseReport,

  /// PageUp/PageDown for full-screen TUIs that scroll their own transcript by
  /// keyboard and ignore wheel reports.
  pageKeys,

  /// Scroll the local scrollback without telling the pane. A normal-buffer pane
  /// prints its transcript and relies on the terminal's own history.
  localBuffer,
}

TerminalScrollAction scrollActionFor({
  required bool paneScrollsByKeyboard,
  required bool mouseTracking,
  required bool altBuffer,
}) {
  if (paneScrollsByKeyboard) return TerminalScrollAction.pageKeys;
  if (!mouseTracking && !altBuffer) return TerminalScrollAction.localBuffer;
  if (mouseTracking) return TerminalScrollAction.mouseReport;
  return TerminalScrollAction.pageKeys;
}

/// A wheel report at cell 1,1. A borderless single pane needs no real position.
String sgrWheelReport({required bool up}) =>
    '\x1b[<${up ? _sgrWheelUp : _sgrWheelDown};1;1M';

String pageKeyReport({required bool up}) => up ? _pageUp : _pageDown;

/// Collapses [step] raw wheel events into one reported event.
class WheelDivider {
  WheelDivider({required this.step});

  final int step;

  int _pending = 0;
  bool? _direction;

  /// Records one raw wheel event and answers whether it completes a step. A
  /// reversal drops the remainder so a change of direction responds at once
  /// instead of spending leftovers from the opposite way.
  bool consume({required bool up}) {
    if (_direction != up) {
      _direction = up;
      _pending = 0;
    }
    _pending += 1;
    if (_pending < step) return false;
    _pending = 0;
    return true;
  }
}

/// Agents whose full-screen TUI keeps its own transcript and scrolls it only by
/// keyboard, ignoring wheel reports. Mirrors the desktop renderer's
/// KEYBOARD_SCROLL_PROVIDERS (TerminalPane.tsx) so both clients agree.
const Set<String> kKeyboardScrollHarnesses = {'opencode', 'kilocode', 'grok'};

bool harnessScrollsByKeyboard(String? harness) =>
    harness != null && kKeyboardScrollHarnesses.contains(harness);

/// Decides what each wheel event from the terminal view turns into on the wire.
///
/// xterm.dart routes every wheel event through [Terminal.mouseHandler], which
/// makes this the one place that can both choose the bytes and rate-limit them
/// without re-implementing the view's drag handling.
class TerminalScrollRouter implements TerminalMouseHandler {
  TerminalScrollRouter(this._terminal, {required String? harness})
      : _paneScrollsByKeyboard = harnessScrollsByKeyboard(harness);

  final Terminal _terminal;
  final bool _paneScrollsByKeyboard;
  final WheelDivider _divider = WheelDivider(step: kTmuxWheelLines);

  @override
  String? call(TerminalMouseEvent event) {
    if (!event.button.isWheel) return defaultMouseHandler(event);
    // Wheel buttons never report a release.
    if (event.buttonState == TerminalMouseButtonState.up) return null;

    final up = event.button == TerminalMouseButton.wheelUp;
    if (!_divider.consume(up: up)) return null;

    switch (scrollActionFor(
      paneScrollsByKeyboard: _paneScrollsByKeyboard,
      mouseTracking: event.state.mouseMode != MouseMode.none,
      altBuffer: _terminal.isUsingAltBuffer,
    )) {
      case TerminalScrollAction.mouseReport:
        return sgrWheelReport(up: up);
      case TerminalScrollAction.pageKeys:
        return pageKeyReport(up: up);
      case TerminalScrollAction.localBuffer:
        return null;
    }
  }
}
