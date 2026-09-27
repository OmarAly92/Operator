# Quick-fix rules

`quick-fix-rules.ts` ports the output and command-line regular expressions of
four built-in terminal quick fixes from
`src/vs/workbench/contrib/terminalContrib/quickFix/browser/terminalQuickFixBuiltinActions.ts`
in Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file):
`gitSimilar`, `gitTwoDashes`, `freePort` and `gitPushSetUpstream`, with their
output windows (anchor, offset, length) and exit condition.

Changes made in the port, and nothing else:

- The expressions `GitCommandLineRegex`, `GitPushCommandLineRegex`,
  `GitSimilarOutputRegex`, `GitTwoDashesRegex`, `FreePortOutputRegex` and
  `GitPushOutputRegex` are kept verbatim.
- Every fix is a command placed in the line editor; none runs. VS Code runs
  the git fixes (`shouldExecute: true`) and frees a port through its own
  process API; here the port fix is the command
  `kill $(lsof -t -iTCP:<port> -sTCP:LISTEN)`.
- The captured branch name, subcommand and option are checked against a
  narrow character class before they are placed in a command, and a fix
  with a control character or a line break is dropped (`safeFix`).
- `gitFastForwardPull`, `gitCreatePr` and the PowerShell rules are not
  ported: they fire on success, open a URL, or target a shell this package
  does not integrate.
- The matcher (`quick-fix.ts`) is written for this package; it follows the
  behaviour of VS Code's `getOutputMatch` window (last lines of the output,
  `anchor: 'bottom'`) but copies no code from it.
