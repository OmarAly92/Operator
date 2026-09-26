# Terminal wishlist: what the user wants next

**Date:** 2026-09-27
**Decision owner:** Omar Aly
**Status:** wishlist, input to the next terminal plans. Nothing here is built.
**Source:** picked by the user from the open items in
`docs/terminal/2026-09-19-terminal-reference-survey.md` (the § numbers below are
that survey's entries). Written in plain language on purpose.

## Order

1. Shift+click and rectangle selection (**the user marked this very important**)
2. Agent signals in Operator (must be reliable and practical)
3. Unseen-output dot and progress bars
4. Shared command history
5. Quick fixes on failed commands
6. Selection that survives a resize
7. Resize while a command is running
8. A cap on piled-up output
9. Stored output that adjusts to a resize
10. Fault-injection tests

## 1. Shift+click and rectangle selection (§1.4, §3.8) — very important

**What the user gets**

- **Shift+click:** click where the text starts, then Shift+click where it ends,
  and everything in between is selected. No dragging, so a selection can span
  long output and scroll without the mouse held down.
- **Alt-drag:** drag with Alt held to select a box (for example one column of a
  table) instead of whole lines. Copy gives only the text inside the box.

**Done when**

- Shift+click extends the current selection from its start to the clicked cell,
  across blocks and across rows that are scrolled out of view.
- Shift+click with no selection selects from where the user last clicked.
- Alt-drag paints a rectangle and copies each row's slice, one line per row.
- Both work in shell panes and in agent (Claude Code) panes, and copy what is
  painted.

## 2. Agent signals in Operator (§6.9, §7.1) — reliable and practical

**What exists:** the terminal package can already read an agent's screen and
say whether it is working, waiting, finished or asking a question, and can give
a short, clean copy of a block's output (spinners and redraws removed).
Operator uses none of it; session status comes only from Claude Code's hooks.

**What the user gets**

1. Status for any command-line agent (Codex, Aider, others), not only ones with
   hooks: working / needs you / done on the board.
2. A quicker "needs you" alert on the card and the phone when an agent shows a
   question.
3. A check on the hooks: a card no longer sticks on the wrong status when a hook
   is missed.
4. Clean "what the agent just did" summaries for the phone and notifications.
5. Later: agents over SSH report their own state through the terminal (the
   agent-state message). Nothing sends it yet.

**The user's requirement: reliable and practical.** In plain terms:

- **No false alarms.** A "needs you" alert must mean the agent really is waiting
  for an answer. A pause in output is not a question.
- **No flicker.** A card does not jump between working and waiting every few
  seconds while an agent thinks.
- **Hooks stay first where they exist.** For Claude Code the hook is the answer;
  the screen signal fills gaps and corrects a status that is clearly stale. It
  never overrides a fresh hook.
- **One alert per question.** The phone is told once, not on every repaint.
- **Measured, not guessed.** Tested on recordings of real Claude Code and Codex
  sessions (working, thinking, asking, done), with the false-alarm count
  written down.
- **Works when the pane is closed.** Status keeps updating for sessions nobody
  is looking at, since that is when it matters most.

## 3. Unseen-output dot and progress bars (§4.8)

**What the user gets**

- **Unseen output:** a small dot on a pane, tab or card meaning "something new
  happened here since you last looked." It clears when you look.
- **Progress bars:** programs that report progress ("40% done", the OSC 9;4
  message) show a bar on the card or tab.

**Done when** the dot appears for new output in a pane that is not on screen,
clears on view, survives a reload, and a progress report shows and clears a bar.

## 4. Shared command history (§6.8)

**What the user gets:** pressing ↑ in the input box shows commands from all
terminals and past sessions, like a normal Mac terminal, not only the current
pane's.

**Done when** ↑ reaches commands run in other panes and before a restart, newest
first, without duplicates in a row.

## 5. Quick fixes on failed commands (§6.6)

**What the user gets:** when a command fails, a suggested fix appears with a
button (for example a failed `git push` offers the command that sets the
upstream). The fix goes into the input box; nothing runs without the user.

## 6. Selection that survives a resize (§1.3, §2.5)

**What the user gets:** a highlight stays on the same words when the window
changes width, and copy gives the same text as before the resize.

## 7. Resize while a command is running (§2.4)

**What the user gets:** resizing while something prints re-flows the older
lines to the new width. Today this works only at an idle prompt.

## 8. A cap on piled-up output (§3.13)

**What the user gets:** a program that floods output (a huge log printed by
mistake) cannot make Operator slow or use a lot of memory. Today the daemon's
pause-when-behind brake covers most cases; this adds a hard limit for the rest.

## 9. Stored output that adjusts to a resize (§6.3)

**What the user gets:** output restored when a pane is reopened or reconnects
looks right at the new size, for example opened on the phone and then on a wide
desktop window.

## 10. Fault-injection tests (§1.14)

**What the user gets:** tests that break things on purpose (dropped
connections, a program that crashes halfway, garbage data) to prove the terminal
survives. Fewer rare, strange freezes that nobody thought to test.
