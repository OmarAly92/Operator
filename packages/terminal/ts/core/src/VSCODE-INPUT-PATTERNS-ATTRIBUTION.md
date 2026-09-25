# Input patterns

`input-patterns.ts` ports `detectsHighConfidenceInputPattern` from
`src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/outputMonitor.ts`
in Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file).

Changes made in the port, and nothing else:

- The nine regular expressions are kept verbatim, in the same order, in a
  module-level array instead of an array literal built on every call.
- VS Code's explanatory comments above each expression are not carried over.
- The broader `detectsLikelyInputRequiredPattern` rules (a bare `: ` or `? `
  at the end of the line) are not ported: VS Code applies them only when it
  knows the command is still running, and this package cannot know that.

The idle timing in `agent-activity.ts` follows the behaviour of VS Code's
`OutputMonitor._waitForIdle` and `PollingConsts` (`MinPollingDuration = 500`,
`MinIdleEvents = 2`, first two polling intervals 500 ms and 1,000 ms) but is
written for this package; no code from those functions is copied.
