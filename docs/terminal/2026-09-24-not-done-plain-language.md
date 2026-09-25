# Terminal: what is not done yet, in plain language (2026-09-24)

A plain-language companion to the status lines in
[`2026-09-19-terminal-reference-survey.md`](2026-09-19-terminal-reference-survey.md)
(checked against the tree on 2026-09-24). The `§` numbers point at the survey
entries. The 26 entries marked **Not done** on 2026-09-24 are grouped below
into 20 items (items 3, 4 and 5 have since been done, roadmap Plans 5 and 1;
items 19 and 20 have since been done, roadmap Plan 3; item 16 has been done and items 17 and 18 decided, roadmap Plan 9); the 16 marked
**Partial** follow with what each is missing.

Two words used throughout:

- **Shell:** a normal terminal where you type commands yourself.
- **Scrollback:** the older output you scroll up to see.

Most of these only matter in the shell. Where you mainly use Claude Code, it
says so.

## Things you would notice

### Search (the find bar)

1. **Search that keeps up (§1.7, §3.12).** While Claude is still writing, the
   find bar doesn't pick up new text that matches, so you have to search
   again. *If done:* matches appear as new output arrives.
   **Done (Plan 2):** matches appear while Claude is still writing, in
   Claude Code panes too — before, the find bar found nothing there.
2. **Smarter search (§2.6).** Search is exact and case-sensitive: "error"
   won't find "Error". *If done:* lowercase searches ignore case, and
   "next/previous" jumps are fast even in huge output.
   **Done (Plan 2):** a lowercase search ignores case, a `.*` button
   switches to patterns, and next/previous steps through the list already
   found.
3. **One look for everything highlighted (§1.8).** Selected text, search
   matches and other marks are drawn by separate code, so they can look
   inconsistent or clash. *If done:* they all look and behave the same, and
   overlap cleanly.
   **Done (roadmap Plan 5):** selection, search matches and your own
   highlights are drawn by one piece of code. Where they overlap, the
   selection is on top, then the current search match, then other matches,
   then your highlights. Selection and search look exactly as before.
4. **Highlight words you care about (§5.6).** You can't tell the terminal
   "always highlight the word ERROR in red". *If done:* important words stand
   out while you scroll.
   **Done (roadmap Plan 5):** Settings → Terminal highlights. Add a word (any
   capitalisation matches) or a pattern (the `.*` button), pick one of five
   colours, and it is coloured in every terminal, Claude Code panes included.

### Pasting

5. **Paste safety (§1.10, §2.11). Done (roadmap Plan 1, 2026-09-24).** When
   the program asked for bracketed paste (Claude Code does), hidden control
   characters are removed before the paste is sent. When it did not, a paste
   with a line break or a hidden control character opens a dialog showing
   the first lines and why, with "Paste" and "Cancel". At a shell prompt
   nothing changed: the paste goes into the line and runs only when you
   press Enter.

### Resizing the window (shell only)

6. **Resizing without a mess (§1.5, §2.4, §5.4).** Making the window
   narrower or wider can push your current line into the history or wrap it
   oddly. *If done:* the text reflows neatly and your prompt stays where it
   is. Claude Code redraws its own screen, so this mostly affects the shell.

### Reusing things

7. **Run a recent command again (§6.8).** Your command history covers only
   this one terminal. *If done:* you can pick commands or folders you used in
   other sessions and earlier days.
8. **Quick fixes (§6.6).** When a command fails with a known error (like
   "command not found"), the terminal doesn't help. *If done:* a small button
   offers the likely fix, such as installing the missing tool.

### Accessibility

9. **Screen reader support (§3.9).** People who can't see the screen and use
   a screen reader can't follow the terminal's output. *If done:* the
   terminal would be usable by blind users.

### Information about each terminal

10. **"New output" and progress badges (§4.8).** A terminal you aren't
    looking at doesn't show that something new happened, or a progress bar
    some programs report. *If done:* a pane or tab can show a dot for new
    output, or a progress bar.

## Things about how the terminal understands the shell

These make blocks (each command with its output) more accurate in the shell.
Claude Code sessions don't use them.

11. **Richer command markers (§1.6, §5.2, §1.18).** The shell tells the
    terminal only "a command started or ended". *If done:* it can also say
    "this is the prompt, this is the command, this is a continuation line",
    so blocks come out exactly right, even with multi-line prompts.
12. **Asking "which part of the screen is what" (§4.6).** Operator can't ask
    "where is the command I typed, and where is its output?" *If done:*
    features like "copy just the output" or "jump to the prompt" get more
    exact.
13. **A trusted "run this command" channel (§6.1).** The "rerun" button can
    only put the command back in the input box; it can't run it safely by
    itself. *If done:* rerun could run the command directly, with a secret
    check so nothing else can fake it.

## Things about Claude Code and agents

14. **Agents telling the terminal what they're doing (§7.1).** *Partly done
    (roadmap Plan 8, 2026-09-25):* the terminal now understands a short
    in-band message an agent can print ("working", "needs you", "idle",
    "done"), which would also travel over SSH. Operator doesn't use it yet —
    it still learns Claude's state from its own side channel on your machine.
15. **The terminal noticing an agent is idle or waiting (§6.9).** *Partly
    done (roadmap Plan 8, 2026-09-25):* the terminal package can now tell
    "busy", "went quiet", "idle" and "asking a yes/no question" on its own,
    and can hand over a block's output with spinner lines and repeated
    redraws stripped out. Operator doesn't use either yet.

## Invisible under-the-hood work

You'd only notice these as fewer rare glitches or slightly less CPU use.

16. **Faster text processing (§1.11) — done (roadmap Plan 9).** Plain text
    is now written a stretch at a time instead of one character at a time;
    Claude Code's long output is read noticeably faster in the
    terminal's own measurements. Codes the terminal doesn't understand are
    kept in a short list developers can read.
17. **Faster line edits (§1.12) — done differently (roadmap Plan 9).**
    Erasing and inserting text in a line now moves the whole stretch at
    once. The "nothing fancy on this row" markers were tried as well and
    made no difference, so they were left out.
18. **Tidier code for control codes (§2.2) — tried and dropped (2026-09-26,
    roadmap Plan 9).** The standard library we checked cannot answer the
    questions Claude Code asks at startup, drops program notifications and
    would change how some colours and codes behave, so the terminal keeps its
    own reader. A new safety net now checks that no future change to that
    reader alters anything on screen.
19. **Safety caps (§2.14) — done (2026-09-25, roadmap Plan 3; unchanged by Plan 9).** Programs can
    push window titles onto a stack; it now stops at 4,096 and drops the
    oldest, so a runaway program cannot grow memory.
20. **Reporting the window size (§1.16) — done (2026-09-25, roadmap Plan 3).**
    A program that asks how big the window or a character cell is, in cells
    or pixels, now gets an answer (Claude Code asks for the cell size).

## The 16 partly done items, and what's missing

- **Selection:** you can't select a rectangle (Alt-drag), extend a selection
  with Shift+click, or pick a block's output with one gesture. Changing the
  window width can also move a selection (§1.3, §1.4, §2.5, §3.8).
- **Window title and other messages from programs — done (2026-09-25,
  roadmap Plan 3):** what Claude says it is doing shows under the session
  name on the board and in the pane header; a program's own "done"
  notification pops up when that pane is not on screen.
- **Minimum contrast option for the theme:** not built (§1.17).
- **Jump to the last command you looked at:** not built (§5.3).
- **Very old output (built 2026-09-25, roadmap Plan 7):** past 200,000 lines
  the oldest text is no longer lost: the helper keeps up to 32 MB of it per
  terminal, and scrolling to the top shows **Load older output**, which brings
  back about 2,000 earlier lines per click. Still missing: loaded lines leave
  again as soon as new output arrives, the old text is not kept across a crash
  or a restart of the helper, and each click briefly pauses a very long pane
  (§5.8).
- **Crash recovery (built 2026-09-24, roadmap Plan 4):** if the helper
  process that runs a session's terminal stops answering for about 15
  seconds, the terminal says "This terminal stopped responding." and offers
  **Restart terminal**, which stops the stuck helper and resumes the agent in
  a new one. If a helper dies (or the Mac reboots), its recent history, up to
  about 10,000 lines, was saved to disk once a minute and comes back when the
  session is restored. Still missing: the board does not show a stuck
  terminal, shells are not checked, and a replay is not redrawn at the sizes
  the output was produced at (§6.3).
- **Typing ahead (done for zsh, roadmap Plan 6, 2026-09-25):** in a zsh
  shell, what you type while a command runs still reaches the running
  program, and whatever it did not read shows up in the input box when the
  command finishes, ready to edit; it runs only when you press Enter. A line
  you finish with Enter while the command runs still runs right after it,
  as before. Still missing: bash and fish shells behave the old way (§7.2).
- The rest are small or test-only: §1.14, §3.6, §3.13, §3.15, §4.4, §4.10,
  §6.2.

## What to pick

For how Operator is used (mostly Claude Code), only a few of these would make
a difference you'd feel:

- **Paste safety (#5):** done (roadmap Plan 1).
- **Search that keeps up, and ignores case (#1, #2):** Claude's output is
  searched often.
- **Claude's window title (partial list):** sessions show what each agent is
  doing right now.
- **Crash recovery (partial list):** a stuck terminal is noticed and restarts
  with one click; built 2026-09-24 (roadmap Plan 4).

Everything else mainly helps the shell, or is invisible.
