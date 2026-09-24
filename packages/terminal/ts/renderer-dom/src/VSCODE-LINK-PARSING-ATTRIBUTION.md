# Link parsing

`link-parsing.ts` and `link-parsing.test.ts` are ports of
`src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts` and
`src/vs/workbench/contrib/terminalContrib/links/test/browser/terminalLinkParsing.test.ts`
from Visual Studio Code (https://github.com/microsoft/vscode, commit `d3c24c3`),
used under the MIT licence (`LICENSE-VSCODE-MIT` beside this file).

Changes made in the port, and nothing else:

- `OperatingSystem` (`Linux | Macintosh | Windows`) becomes `LinkOs = "posix" | "windows"`;
  the test table's Linux and macOS rows both run as `"posix"`.
- `Lazy<RegExp>` becomes a memoising function.
- `I`-prefixed interface names lose the prefix (`ParsedLink`, `LinkSuffix`, `LinkPartialRange`).
- The test runner is vitest: `suite` → `describe`, `test` → `it`, `deepStrictEqual(a, b)` →
  `expect(a).toStrictEqual(b)`, `strictEqual(a, b)` → `expect(a).toBe(b)`, `ok(x)` →
  `expect(x).toBeTruthy()`; `ensureNoDisposablesAreLeakedInTestSuite` is dropped.
- The three caps of `terminalLocalLinkDetector.ts:22-34` are exported as constants here so
  the provider that consumes the grammar reads them from one place.
- Comments are kept as they are in the source (a port keeps its author's comments).
- The test file is split to stay under the package's 600-line limit: `link-parsing.test.ts`,
  `link-parsing.diffs.test.ts`, and the shared test table in `link-parsing-cases.ts`.
