# Input patterns

`input_pattern_sources.rs` and `input_patterns.rs` port `detectsHighConfidenceInputPattern` from
`src/vs/workbench/contrib/terminalContrib/chatAgentTools/browser/tools/monitoring/outputMonitor.ts`
in Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file).

Changes made in the port, and nothing else:

- The nine regular expressions are kept in the same order in
  `input_pattern_sources.rs`; the JavaScript `i` flag is written as `(?i)`.
  The crate's `build.rs` compiles each one with `regex-automata` into a
  minimized sparse DFA at build time, and `input_patterns.rs` searches those,
  so no regex compiler ships in the wasm (`tests/input_pattern_parity.rs`
  checks the automata against `regex-automata`'s `meta::Regex`).
- VS Code's explanatory comments above each expression are not carried over.
- The broader `detectsLikelyInputRequiredPattern` rules (a bare `: ` or `? `
  at the end of the line) are not ported: VS Code applies them only when it
  knows the command is still running, and this package cannot know that.

The idle timing in `activity.rs` (and `ts/core/src/agent-activity.ts`) follows the behaviour of VS Code's
`OutputMonitor._waitForIdle` and `PollingConsts` (`MinPollingDuration = 500`,
`MinIdleEvents = 2`, first two polling intervals 500 ms and 1,000 ms) but is
written for this package; no code from those functions is copied.
