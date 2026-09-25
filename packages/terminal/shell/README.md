# `packages/terminal/shell/`

Shell bootstrap scripts. The package is the authority on the spawn contract
for each shell; the host asks for a `SpawnRecipe` and pipes bytes. The
bootstrap scripts are loaded by the host into a real shell process via the
recipe's `argv`.

## What these scripts do

`zsh.sh` registers two hooks with `add-zsh-hook`:

- `preexec` records the command and emits `OSC 133 C` (output start).
- `precmd` emits `OSC 133 D ; <exit>` (command finished) and one
  `OSC 7000 ; v=1 ; id=… ; cmd=… ; cwd=… ; branch=… ; exit=… ST` mark
  carrying the exact command text, working directory, current git branch,
  and the previous command's exit code, then emits `OSC 133 A` (prompt
  start) for the next prompt.

The branch read is the only command run for the package's own bookkeeping;
it is gated on `git rev-parse --is-inside-work-tree` and tolerates git
being absent.

`zsh.sh` also registers a `line-init` zle hook widget. It emits `OSC 133 B`
and `OSC 7000 ; v=1 ; input-ready=1`, and at the first prompt after a
command it reads the input already waiting on the tty, gives it straight
back to zle with `zle -U`, and reports it as `OSC 7000 ; v=1 ;
typeahead=<percent-encoded UTF-8>` when it is 1–256 characters with no
control character (`protocol/SPEC.md` §4.5). The shell keeps the text; a
line editor that adopts it clears it with `^U`. `bash.sh` and `fish.fish`
do not report typeahead.

## What these scripts do NOT do

The bootstrap is additive-only. The script must NOT:

- remove, reorder, or stash the user's hook functions (no direct
  `precmd_functions` mutation);
- add or remove any `bindkey` binding;
- reference any third-party prompt framework by name (no `p9k`, no
  `starship`, no `oh-my-zsh` carve-outs);
- execute any command in the user's session for our own bookkeeping
  beyond the branch read;
- inspect or rewrite the user's ssh arguments;
- set `PROMPT` or `PS1` (Phase 2 owns prompt suppression; the brief
  pins `suppressPrompt: true` to throw at runtime in Phase 1a).

The full contract is in `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
§8 (shell bootstrap, additive-only) and §8.1 (prompt suppression off in
Phase 1a).

## Tests

`zsh.test.mjs`, `bash.test.mjs` and `fish.test.mjs` run under `node --test`
against the real shells; the pty cases drive them through `tmux`
(`pty.mjs`) and skip when the shell or tmux is missing. Run them with a
UTF-8 locale (`LANG=C.UTF-8 LC_ALL=C.UTF-8`): one case types `é` and `€`.
`go/bootstrap/shell/` holds the byte copies the daemon embeds;
`go/bootstrap/bootstrap_test.go` `TestScriptCopyIsInSyncWithShellDir` fails
when they drift.
