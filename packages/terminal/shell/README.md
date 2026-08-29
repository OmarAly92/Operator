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

`zsh.test.mjs` runs five `node --test` cases against a real `zsh` binary.
The cases verify the happy path, precmd preservation, keymap preservation,
idempotence under a second source, and prompt preservation. The test
skips on hosts without `zsh` rather than failing.
