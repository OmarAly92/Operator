# Agent-TUI Plan E — Act on What Claude Code Prints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The things Claude Code prints become things the user can act on — a soft-wrapped line copies as one line, a URL or `path:line` under the pointer underlines and opens with the platform modifier, a chord labels every visible match so a path can be opened from the keyboard, OSC 8 hyperlinks the agent emits are kept and openable, host-supplied secret patterns paint as masked cells that copy masked, and every block carries the clock it started and finished at — while with no pointer, no chord and no host patterns the transcript paints exactly as today.

**Architecture:** Two model changes land first, each through the incremental `ExportBuffers` path: a per-row `wrapped` byte (so the renderer can join logical lines) and a sixth style-run word carrying an OSC 8 link id interned per core in a capped, never-reclaimed registry (Warp `hyperlink_registry.rs`). Block records gain `started_at_ms`/`finished_at_ms`, filled from the `feed_at` clock when the shell hook did not supply them. Everything visible lives in `ts/renderer-dom` as overlays positioned from row geometry — never as edits to pooled row elements — behind the pointer, the hint chord or a host pattern list: a `Linkifier` (hover → per-logical-line providers → underline overlay → modifier click, xterm.js `Linkifier.ts`), a hint session (WezTerm `quickselect.rs` rule set and labels, Kitty's `path:line`), and a redaction pass (Warp `secrets.rs`) that the copy path honours. `TerminalSurface` forwards pointer and keyboard events and three new `HostCapabilities` seams; Operator implements them in `frontend/` (Tauri commands for the file system, a daemon route for the pattern list, notifications for `onBlockFinished`).

**Tech Stack:** Rust (`vt-core`, `vt-wasm` via wasm-bindgen, `vt-host` C-ABI wasm run by wazero), Go (`backend/internal/adapters/runtime/ptyhost/vtwasm`, `backend/internal/redact`, `backend/internal/httpd`), TypeScript (`ts/core`, `ts/renderer-dom`, `ts/react`, `frontend/`), Tauri 2 (`frontend/src-tauri`), Vite + Playwright benches.

**Spec:** `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` — Plan E covers exactly Part 5 ("Act on what Claude Code prints (additive UI only)"), gated on Plan B (landed `ba6dd6d35`; A `9a71794e9`, C `7412050f4` and D `b4c3067b2` have also landed — confirm with `git log --oneline | grep -i "merge: Plan"`). Survey entries cited: `docs/superpowers/specs/2026-09-19-terminal-reference-survey.md` §1.15, §2.7, §3.7, §4.5, §4.7, §5.3, §5.5, §6.2, §6.4, §7.3, §7.4. Read `TERMINAL.md` end to end before starting — §2 (snapshot layout and the checklist for a per-row field; the five-word style run and the cell-span buffer since Plan D), §3 (product independence), §4.12 (arrow over the transcript, hand only over a link), §4.13 (the selection is the renderer's model), §5 (the first known gap, "copy joins wrapped rows with newlines", is what Task 1 closes), §6 (verify-and-ship recipe).

## Global Constraints

Every task inherits these; they are the spec's "Global constraints" plus `TERMINAL.md` §3.

- `packages/terminal` stays product-independent (`TERMINAL.md` §3.1): no Operator import, path, default or concept inside it. Rule sets, caps, the label alphabet, the redaction mask character and the URL grammar are package constants; "open in editor", Operator's secret patterns, the notification threshold and ticket text are host-side (`frontend/`, `backend/`). Gate: could a second, non-Operator host use this?
- No comments in new code (user's global instruction). Existing comments may be corrected when they become false. A code comment that cites a reference names the repository and path (`vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts`, `wezterm/wezterm-gui/src/overlay/quickselect.rs`, `kitty/kittens/hints/marks.go`, `warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs`, `xterm.js/src/browser/Linkifier.ts`, `xterm.js/addons/addon-web-links/src/WebLinksAddon.ts`, `alacritty/alacritty/src/display/hint.rs`, `warp/crates/warp_terminal/src/model/grid/grid_handler.rs`) the way `styles.css` cites Warp — such citations are the one kind of new comment permitted.
- A `vt-core` change is live only after **both** wasm artifacts are rebuilt (`vt_core` for the renderer via `npm run build:wasm -- --force`; `vt_host.wasm` built with `cargo build --release -p vt-host --target wasm32-unknown-unknown` and copied into `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/`) and the daemon is rebuilt (`npm --prefix frontend run build:daemon`). Old pty-host processes keep the old wasm for the life of the session; every such task ends with "restart the daemon and the app".
- TDD: failing test first, run it, minimal implementation, run it, commit. Every `TERMINAL.md` §4 guard keeps passing.
- Rust: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` from `/Users/omaraly/development/AI/Operator/packages/terminal`. TS: `npm run build:ts` then `npx vitest run` in each of `ts/core`, `ts/renderer-dom`, `ts/editor`, `ts/react` (the react package resolves renderer-dom through its built `dist`, so build first); `npx tsc --noEmit -p .` in `/Users/omaraly/development/AI/Operator/frontend`. Go: `go test ./internal/adapters/runtime/ptyhost/...` in `/Users/omaraly/development/AI/Operator/backend` (and `go test ./internal/redact/... ./internal/httpd/... ./internal/session_manager/...` where a task touches them). Tauri: `cargo test` and `cargo check` in `/Users/omaraly/development/AI/Operator/frontend/src-tauri` where a task touches it.
- Changelog: `packages/terminal/CHANGELOG.md`, "Unreleased", one entry per behaviour change. Commits go to `development` with the `Co-Authored-By` trailer the harness gives you.
- Use absolute paths in every shell command (`TERMINAL.md` §6: parallel Bash calls share the working directory).
- **Feel gate:** every task ends with `npm run bench:feel` from `/Users/omaraly/development/AI/Operator/packages/terminal` and it must print `PASS feel gate: zero pixel diff` — with no hover, no chord and no host patterns. **No task in this plan declares a pixel change**; the user's words are "currently it feels perfect". A visible affordance appears only in response to the user's pointer or keyboard, or to a pattern list the host chose to pass. Tasks 6, 7 and 8 also record a side-by-side screenshot of their affordance through `npm run bench:affordances -- --action <name>` (Task 6 adds the script), never diffed, so the user can see it before it ships.
- `npm run bench:selection` runs after any change to row/glyph DOM or the copy path (Tasks 1, 2, 6, 7, 8).
- Do not change behaviour the spec does not ask for: no selection-gesture changes, no default-on decorations, no theme or font changes, no mobile (`packages/mobile`) changes, no Part 4 flag defaults, no touch to the capture journal (`backend/internal/terminal/capture.go`).

## Decisions made here (the brief asked for a reason on each)

- **OSC 8 is parsed in `Parser::osc_dispatch`, not as a `MarkEvent`.** An OSC 8 changes the printer's *pen* — every cell printed after it carries the link until the closing `OSC 8 ;; ST` — exactly the cadence of SGR, which `csi_dispatch` handles in the same `vte::Perform` impl. vte delivers `osc_dispatch` at the byte where the sequence ends and `print` for every cell after it, so the pen change lands between the right prints by construction; that is the stream-order rule of `TERMINAL.md` §4.15 (an event lands only after the bytes before it were parsed) satisfied without the offset dance `feed_raw` does for marks. A `MarkEvent::Hyperlink` would be applied through `apply_event` *after* `advance_vte` had already printed the bytes up to the mark's offset — correct too, but it would put pen state in the block state machine, and `crates/marks` decodes only 133 / 7 / 7000 by design (`osc.rs:21`). The history receiver's `ScreenPerform` gets the same arm so a replayed chunk keeps its links.
- **The link id is a sixth style-run word, not a separate span buffer.** `CellStyle` gains `link: u16` (0 = none), which fills the two bytes of padding after `attrs: u16` — `size_of::<CellStyle>()` stays 16 (pinned by a test). The `AttributeMap<CellStyle>` then splits and merges runs at link boundaries for free, survives rewrap (offsets do not move), eviction and trim with zero new bookkeeping, and the alternate screen gets links through the same `style_pairs`. A per-row span buffer shaped like `cellSpans` would need its own dead/history accounting in `ExportBuffers`, a second `AltSnapshot` copy, and a second lookup on hover. Cost: one `u32` per exported run (`STYLE_RUN_WORDS = 6`), about 240 KB at the 60k-row fixture's 60,277 runs — measured in Task 10, not assumed. **The registry itself sits outside `Limits { bytes }`**: `Parser::trim_to` weighs `content.resident_bytes() + styles.byte_len()` (`parser.rs:629`) and `memory_stats` reports the same two (`lib.rs:111-118`), so interned URIs are neither counted nor trimmed. At the caps that is a bounded ~8.5 MB worst case (4096 × `MAX_URI_BYTES`) on top of a 128 MiB budget, never reclaimed, which is Warp's own trade (`hyperlink_registry.rs:11-15`) and why the caps are the design rather than an afterthought. Task 10 reports the measured table size **against** the budget, not beside it, and `TERMINAL.md` §5 records the exclusion.
- **The core's clock is epoch milliseconds in both cores.** The Go mirror already feeds `time.Now().UnixMilli()` (`vtwasm.go:111`) and the shell hook's `start_ms`/`end_ms` are epoch (`protocol/SPEC.md:130`); the TS core fed `performance.now()`, a page-relative clock. Block timestamps must be comparable across the three, so `TerminalCore.feed` and the renderer's `tick` switch to `Date.now()`. The DEC 2026 deadline logic only compares a feed's clock with a tick's clock, so it is unaffected as long as both use the same one; `drain()`'s 12 ms budget keeps `performance.now()` for its sub-millisecond resolution.
- **Two URL grammars, on purpose.** The hover linkifier uses xterm.js's `strictUrlRegex` (`addon-web-links/src/WebLinksAddon.ts:21`): `https?` only, trailing punctuation excluded, no false positives under the pointer. Hint mode uses WezTerm's `url` pattern (`quickselect.rs:30`: `https?://|git@|git://|ssh://|ftp://|file://`) because that is the rule set the spec names for the chord. Survey §3.7 asked for the choice to be made after trying both on a Claude Code transcript; the act-probe fixture (Task 6) is that transcript in miniature and both are exercised there.
- **`resolvePath` is a Tauri command, not a daemon route.** The check is "does this file exist relative to this cwd", the desktop and the daemon share the file system, and a Tauri command is one function with no API spec regeneration; the mobile client renders with its own xterm fork and is out of scope. The redaction pattern list *is* a daemon route (`GET /api/v1/redaction/patterns`), because the daemon already owns the patterns and the user's own `redact-patterns.txt` (`backend/internal/redact/userpatterns.go`); two hand-kept lists across Go and TS would drift.
- **Two files named `logical-lines.ts`, and the renderer's builds on the core's.** `ts/core/src/logical-lines.ts` works in snapshot rows and answers `TerminalCore.logicalLines(range)` — the API the spec names, usable by any host with a snapshot. `ts/renderer-dom/src/logical-lines.ts` works in the renderer's stable-row, per-block space and carries link runs, because that is what the linkifier, hint mode and redaction address. The shapes genuinely differ (`LogicalLine` against `LogicalLineView`), so one file cannot serve both; what must not be duplicated is the *join*, and it is not: the renderer's `logicalLineAt` imports `joinLogicalLine` from `@operator/terminal-core` and derives its `text`/`rowOffsets` from that one function, deriving nothing itself. A change to how pieces join lands in both by construction. Task 10 records the pairing in `TERMINAL.md` §2 so a later reader does not "unify" them by re-deriving one.
- **`onBlockFinished` is computed by `DomBlockRenderer`, which already decodes blocks on every paint**, and `visible` is answered there from the container (in layout, not `inert`, document visible). Putting it in `ts/core` would still only fire when someone calls `snapshot()`, and `visible` is a DOM question.
- **Logical lines across a reopen are single rows.** `Parser::apply_history_chunk` prepends the rows `HistoryReceiver::take` built, and `history_row` builds every one of them with `wrapped: false` (`crates/vt-core/src/history.rs:193`; recorded in `TERMINAL.md` §5), so a reopened pane cannot rejoin lines the mirror soft-wrapped before the reopen. Task 1 exports what the model has; it does not change the chunk protocol. Recorded again in Task 10.
- **Wrapped screen rows export their trailing blanks.** `export_screen_row` trims trailing blanks so a partially filled row exports only its text; for a row the printer soft-wrapped that trim loses the space a word break landed on (`abc ` + `def` would join as `abcdef`). `scrollback::commit_row` already keeps the full width for a wrapped row (`scrollback.rs:14-20`); Task 1 makes the screen export agree with it. Spaces at the end of a `white-space: pre` span paint nothing, and the feel gate proves it.

## Shapes — the single source of truth

Every task's code must match these exactly (the self-review checks it).

**Per-row wrapped (Task 1).** Rust `ExportedRow.wrapped: bool`; `GridSnapshot.row_wrapped: Vec<bool>` with `GridSnapshot::row_wrapped(index: usize) -> bool`; `ExportBuffers::row_wrapped() -> &[u8]` (1 = the next row continues this one); vt-wasm `row_wrapped_ptr() -> *const u8`, `row_wrapped_len() -> usize`. TS `TerminalSnapshot.rowWrapped: Uint8Array` (same meaning, one byte per row). `ts/core/src/logical-lines.ts`: `LogicalLine = Readonly<{ firstRow: number; rowCount: number; text: string; rowOffsets: readonly number[] }>` (flat snapshot rows; `rowOffsets[i]` is the UTF-16 offset in `text` where row `i` of the line starts) and `joinLogicalLine(texts: readonly string[]): { text: string; rowOffsets: number[] }`; `TerminalCore.logicalLines(range: RowRange): LogicalLine[]` over `[range.start, range.end)` flat rows, extending the first and last lines to their full extent. renderer-dom `TextRows.rowWrapped(blockId: string, row: number): boolean` (stable-row space, like `rowText`).

**Hyperlinks (Tasks 2–3).** `crates/vt-core/src/hyperlink.rs`: `pub const MAX_DISTINCT_ENTRIES: usize = 4096; pub const MAX_URI_BYTES: usize = 2083; pub const MAX_ID_BYTES: usize = 256; pub type LinkId = u16;` `pub struct Hyperlink { pub id: Option<String>, pub uri: String }`; `pub struct HyperlinkRegistry` with `intern(&mut self, link: Hyperlink) -> Option<LinkId>` (1-based; `None` past the cap or over the byte cap; the same `Hyperlink` returns the same id), `uri(&self, id: LinkId) -> Option<&str>`, `len()`, `is_empty()`; `pub fn parse_osc8(params: &[&[u8]]) -> Option<Hyperlink>` taking the fields **after** `b"8"`. `CellStyle.link: LinkId` (0 = none; `CellStyle::DEFAULT.link == 0`; SGR 0 keeps it). Style run: `(end, fg, bg, attrs, underline, link)`, `STYLE_RUN_WORDS = 6` in `crates/vt-wasm/src/export.rs` and `ts/core/src/style-runs.ts`, plus `STYLE_WORD_LINK = 5` in TS. `GridSnapshot.link_text: Vec<u8>`, `GridSnapshot.link_ranges: Vec<(u32, u32)>` (index `id - 1`), `GridSnapshot::link_uri(id: LinkId) -> Option<&str>`; `TerminalCore::hyperlink_count() -> usize`, `TerminalCore::hyperlink_uri(id: LinkId) -> Option<&str>`; `ExportBuffers::link_text() -> &[u8]`, `link_ranges() -> &[u32]`; vt-wasm `link_text_ptr/len`, `link_ranges_ptr/len`. TS `TerminalSnapshot.linkRanges: Uint32Array`, `TerminalSnapshot.linkText: Uint8Array`, `TerminalCore.linkUri(id: number): string | null`.

**Block timestamps (Task 4).** `BlockGrid::set_clock(&mut self, now_ms: u64)`, `BlockGrid::note_output(&mut self)`, `BlockGrid::trailing_started_at_ms(&self) -> Option<u64>`; `BlockRecord.started_at_ms: Option<u64>`, `BlockRecord.finished_at_ms: Option<u64>`; `BLOCK_RECORD_WORDS = 18` — words 14/15 `started_at_ms` lo/hi, 16/17 `finished_at_ms` lo/hi, `(u32::MAX, u32::MAX)` for `None` (the same encoding as `duration_ms` in words 6/7). TS `BlockView.startedAtMs: number | null`, `BlockView.finishedAtMs: number | null`. renderer-dom `ts/renderer-dom/src/block-finished.ts`: `BlockFinishedEvent = Readonly<{ id: BlockId; exitCode: number | null; durationMs: number | null; visible: boolean }>`, `finishedBlocks(previous: ReadonlyMap<BlockId, BlockState>, blocks: readonly BlockView[]): BlockView[]`, `rendererVisible(container: HTMLElement): boolean`; `DomBlockRenderer.onBlockFinished(listener: (event: BlockFinishedEvent) => void): () => void`; `TerminalSurface` prop `onBlockFinished?: (event: BlockFinishedEvent) => void`.

**Link grammar (Task 5).** `ts/renderer-dom/src/link-parsing.ts`: `type LinkOs = "posix" | "windows"`; `ParsedLink = { path: LinkPartialRange; prefix?: LinkPartialRange; suffix?: LinkSuffix }`, `LinkSuffix = { row: number | undefined; col: number | undefined; rowEnd: number | undefined; colEnd: number | undefined; suffix: LinkPartialRange }`, `LinkPartialRange = { index: number; text: string }`; `detectLinks(line: string, os: LinkOs): ParsedLink[]`, `detectLinkSuffixes(line: string): LinkSuffix[]`, `getLinkSuffix(link: string): LinkSuffix | null`, `removeLinkSuffix(link: string): string`, `removeLinkQueryString(link: string): string`, `toLinkSuffix(match: RegExpExecArray | null): LinkSuffix | null`; `LINK_MAX_LINE_LENGTH = 2000`, `LINK_MAX_RESOLVED_PER_LINE = 10`, `LINK_MAX_RESOLVED_LENGTH = 1024`.

**Linkifier (Task 6).** `ts/renderer-dom/src/clusters.ts` adds `rowCoordinates(text, spans): Coordinate[]` (`Coordinate = Readonly<{ cell: number; byte: number; offset: number }>`, one per cluster start plus a final sentinel), `cellAtOffset(text, spans, offset)`, `cellAtByte(text, spans, byte)`, `offsetAtByte(text, spans, byte)`. `TextRows` gains optional `rowLinkRuns?(blockId, row): ArrayLike<number>` (flat triples `byteStart, byteEnd, linkId` for runs with `linkId !== 0`) and `linkUri?(id: number): string | null`. `ts/renderer-dom/src/logical-lines.ts`: `LinkRange = Readonly<{ blockId: string; startRow: number; startCell: number; endRow: number; endCell: number }>` (stable rows, `endCell` exclusive on `endRow`), `LinkRun = Readonly<{ startOffset: number; endOffset: number; linkId: number }>`, `LogicalLineView = Readonly<{ blockId: string; firstRow: number; rowCount: number; text: string; rowOffsets: readonly number[]; linkRuns: readonly LinkRun[]; rangeOf(startOffset: number, endOffset: number): LinkRange; linkUri(id: number): string | null }>`, `logicalLineAt(rows: TextRows, blockId: string, row: number): LogicalLineView | null`, `rangeContains(range: LinkRange, row: number, cell: number): boolean`. `ts/renderer-dom/src/link-providers.ts`: `LinkKind = "hyperlink" | "url" | "path"`, `DetectedLink = Readonly<{ kind: LinkKind; text: string; uri?: string; path?: string; line?: number; column?: number; range: LinkRange }>`, `LinkProvider = (line: LogicalLineView) => Promise<readonly DetectedLink[]>`, `hyperlinkProvider`, `urlProvider`, `createPathProvider(resolve: (path: string, cwd: string) => Promise<string | null>, cwdOf: (blockId: string) => string, os: LinkOs): LinkProvider`, `DEFAULT_LINK_PROVIDERS = [hyperlinkProvider, urlProvider]`. `ts/renderer-dom/src/linkifier.ts`: `class Linkifier { constructor(deps: { rows(): TextRows; generation(): number; providers(): readonly LinkProvider[]; onChange(): void }); hover(point: SelectionPoint | null): void; refresh(): void; invalidate(): void; current(): DetectedLink | null; dispose(): void }` (`invalidate()` clears the per-line hover cache before calling `refresh()`; needed because `setLinkProviders` swaps the provider list without moving `deps.generation()`, so a bare `refresh()` would still answer from a promise built against the replaced providers — found executing Task 6, not anticipated when this section was written). `ts/renderer-dom/src/decorations.ts`: `DecorationBox = Readonly<{ left: number; top: number; width: number; height: number }>`, `rangeBoxes(range: LinkRange, rows: readonly RenderedRow[], cellWidth: number, container: HTMLElement): DecorationBox[]` (container coordinates, scroll offset included), `paintBoxes(layer: HTMLElement, className: string, boxes: readonly DecorationBox[], labels?: readonly string[]): void`. `DomBlockRenderer`: `hoverAt(x: number, y: number): void`, `clearHover(): void`, `hoveredLink(): DetectedLink | null`, `onLinkHover(listener: (link: DetectedLink | null) => void): () => void`, `setLinkProviders(providers: readonly LinkProvider[]): void`. CSS: `.terminal-decorations`, `.terminal-link-underline`, `.terminal-link-hover .terminal-block, .terminal-link-hover .terminal-alt-surface { cursor: pointer }`. react `selection-gesture.ts`: `linkModifierHeld(event, mac): boolean` (mac → `metaKey` alone; else `ctrlKey` alone).

**Hint mode (Task 7).** `ts/renderer-dom/src/hint-rules.ts`: `HintRule = Readonly<{ id: string; regex: RegExp; capture: "whole" | "last" }>` (`"last"` = the highest-numbered capture group that matched, WezTerm `mux/src/localpane.rs:731-745`; `"whole"` = the whole match), `DEFAULT_HINT_RULES: readonly HintRule[]` (14 rules in this order: `file-line` first, then WezTerm's `markdown-url, url, diff-a, diff-b, docker, path, color, uuid, sha, ip, ipv6, address, number` — at equal start the earlier rule wins, so Kitty's `path:line` beats WezTerm's bare `path`), `HINT_RULE_HYPERLINK = "hyperlink"`, `fileLineFields(match: RegExpExecArray): { path: string; line: number }`; `ts/renderer-dom/src/hint-labels.ts`: `DEFAULT_HINT_ALPHABET = "asdfqwerzxcvjklmiuopghtybn"`, `computeLabelsForAlphabet(alphabet: string, count: number): string[]`; `ts/renderer-dom/src/hint-mode.ts`: `HintMatch = Readonly<{ ruleId: string; text: string; path?: string; line?: number; range: LinkRange }>`, `HintEvent = Readonly<{ ruleId: string; text: string; path?: string; line?: number }>`, `collectHintMatches(lines: readonly LogicalLineView[], rules: readonly HintRule[]): HintMatch[]`, `class HintSession { constructor(matches: readonly HintMatch[], alphabet: string); labelled(): readonly { label: string; match: HintMatch }[]; type(character: string): HintMatch | null; backspace(): void; typed(): string }` (labels are assigned bottom-right first and shared by matches with identical text, WezTerm `quickselect.rs` `recompute_results`); `DomBlockRenderer.hintBegin(rules?: readonly HintRule[]): number`, `hintType(character: string): HintEvent | null`, `hintBackspace(): void`, `hintCancel(): void`, `hintActive(): boolean`. CSS `.terminal-hint-match`, `.terminal-hint-label`. react `selection-gesture.ts`: `isHintChord(event): boolean` (Ctrl+Shift+Space on every platform, WezTerm `commands.rs:828`); `TerminalSurface` prop `onHint?: (hint: HintEvent) => void`.

**Redaction (Task 8).** ts/core `types.ts`: `SecretPattern = Readonly<{ source: string; flags?: string }>` and `HostCapabilities.secretPatterns?: readonly SecretPattern[]`. `ts/renderer-dom/src/redaction.ts`: `REDACTION_MASK = "*"`, `compileSecretPatterns(patterns: readonly SecretPattern[]): RegExp[]`, `SecretRange = Readonly<{ start: number; end: number }>`, `secretRanges(text: string, regexes: readonly RegExp[]): SecretRange[]` (a leading capture group at the match start is kept visible, a trailing one at the match end is kept visible, overlaps merged), `RedactionMatch = Readonly<{ key: string; range: LinkRange }>`, `redactionMatches(line: LogicalLineView, regexes: readonly RegExp[]): RedactionMatch[]`, `maskedTextRows(rows: TextRows, regexes: readonly RegExp[], revealed: ReadonlySet<string>): TextRows`; `DomBlockRenderer.setSecretPatterns(patterns: readonly SecretPattern[]): void`, `revealSecretAt(x: number, y: number): void`. CSS `.terminal-redaction`.

**Host seams (Task 9).** `HostCapabilities.resolvePath?(path: string, cwd: string): Promise<string | null>` (absolute path when it exists, else `null`); `HostCapabilities.openPath?(path: string, line?: number, column?: number): Promise<void>`; `HostCapabilities.secretPatterns?: readonly SecretPattern[]`. Operator: Tauri commands `resolve_path(base: Option<String>, path: String) -> Result<Option<String>, String>` and `open_path(path: String) -> Result<(), String>` in `frontend/src-tauri/src/native.rs`; bridge `app.resolvePath(base: string | null, path: string): Promise<string | null>`, `app.openPath(path: string): Promise<void>`; daemon `GET /api/v1/redaction/patterns` → `RedactionPatternsResponse { patterns: RedactionPattern[] }`, `RedactionPattern { source: string; flags: string }` from `redact.JSPatterns()`; `useUiStore().terminalSecretRedaction: boolean` + `setTerminalSecretRedaction`; `BlockTerminal` props `workspacePath?: string`.

## File structure

| Task | Files |
|---|---|
| 1 | `crates/vt-core/src/{grid.rs,lib.rs}`, `crates/vt-core/tests/{logical_lines.rs,common/mod.rs}`, `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`, `ts/core/src/{types.ts,terminal-core.ts,terminal-core.test.ts,logical-lines.ts,logical-lines.test.ts,index-browser.ts}`, `ts/renderer-dom/src/{selection-text.ts,selection-text.test.ts,selection-view.ts,terminal-selection.test.ts}`, `backend/.../vtwasm/assets/vt_host.wasm`, `frontend/src/renderer/test/setup.ts` (only if `tsc` demands), `CHANGELOG.md` |
| 2 | `crates/vt-core/src/{hyperlink.rs,lib.rs,style.rs,sgr.rs,parser.rs,grid.rs,screen/snapshot.rs}`, `crates/vt-core/tests/osc8.rs`, `crates/vt-wasm/src/{export.rs,lib.rs}`, `crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`, `crates/vt-host/src/lib.rs` (compile only), `ts/core/src/{style-runs.ts,types.ts,terminal-core.ts,terminal-core.test.ts,index-browser.ts}`, the hand-built style arrays in `ts/renderer-dom/src/{alt-surface,attributes,block-glyphs,cursor,width-cache}.test.ts`, `CHANGELOG.md` |
| 3 | `crates/vt-host/src/lib.rs`, `crates/vt-core/src/{history.rs,lib.rs,parser.rs}`, `crates/vt-core/tests/osc8.rs`, `backend/internal/adapters/runtime/ptyhost/vtwasm/{replay_test.go,assets/vt_host.wasm}`, `CHANGELOG.md` |
| 4 | `crates/vt-core/src/{block.rs,block_grid.rs,parser.rs,lib.rs,grid.rs}`, `crates/vt-core/tests/block_timestamps.rs`, `crates/vt-wasm/src/export.rs`, `crates/vt-wasm/tests/exit_encoding.rs`, `ts/core/src/{blocks.ts,types.ts,terminal-core.ts,block-contract.test.ts,terminal-core.test.ts}`, `ts/renderer-dom/src/{block-finished.ts,block-finished.test.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,index.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`, `CHANGELOG.md` |
| 5 | `ts/renderer-dom/src/{link-parsing.ts,link-parsing.test.ts,VSCODE-LINK-PARSING-ATTRIBUTION.md}` |
| 6 | `ts/renderer-dom/src/{clusters.ts,clusters.test.ts,logical-lines.ts,logical-lines.test.ts,link-providers.ts,link-providers.test.ts,linkifier.ts,linkifier.test.ts,decorations.ts,decorations.test.ts,selection-text.ts,selection-view.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,styles-parity.test.ts,index.ts}`, `ts/react/src/{selection-gesture.ts,selection-gesture.test.ts,TerminalSurface.tsx,TerminalSurface.mouse.test.tsx}`, `bench/agent-session/probes/act-probe/{recording,size.json}`, `bench/agent-session/make-act-probe.mjs`, `bench/agent-session/affordance-gate.mjs`, `bench/agent-session/main.ts`, `bench/agent-session/session-api.test.mjs`, `bench/agent-session/fixtures.test.mjs`, `bench/agent-session/baselines/act-probe/`, `package.json`, `CHANGELOG.md` |
| 7 | `ts/renderer-dom/src/{hint-rules.ts,hint-rules.test.ts,hint-labels.ts,hint-labels.test.ts,hint-mode.ts,hint-mode.test.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,index.ts}`, `ts/react/src/{selection-gesture.ts,selection-gesture.test.ts,TerminalSurface.tsx,TerminalSurface.hint.test.tsx}`, `bench/agent-session/{main.ts,affordance-gate.mjs,session-api.test.mjs}`, `CHANGELOG.md` |
| 8 | `ts/core/src/{types.ts,index-browser.ts}`, `ts/renderer-dom/src/{redaction.ts,redaction.test.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,index.ts}`, `ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`, `bench/agent-session/{main.ts,affordance-gate.mjs,session-api.test.mjs}`, `CHANGELOG.md` |
| 9 | `frontend/src-tauri/src/{native.rs,lib.rs}`, `frontend/src-tauri/capabilities/default.json`, `frontend/src/shared/operator-bridge.ts`, `frontend/src/renderer/lib/{tauri-bridge.ts,bridge.ts,tauri-bridge.test.ts,terminal-secret-redaction.ts,terminal-secret-redaction.test.ts,redaction-patterns.ts,redaction-patterns.test.ts}`, `frontend/src/renderer/stores/ui-store.ts`, `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx`, `frontend/src/renderer/i18n/en.json`, `frontend/src/renderer/components/{BlockTerminal.tsx,BlockTerminal.test.tsx,TerminalPane.tsx}`, `backend/internal/redact/{redact.go,jspatterns.go,jspatterns_test.go}`, `backend/internal/httpd/controllers/{redaction.go,redaction_test.go}`, `backend/internal/httpd/api.go`, `backend/internal/httpd/apispec/specgen/build.go`, `backend/internal/httpd/apispec/openapi.yaml` (generated), `frontend/src/api/schema.ts` (generated), `backend/internal/session_manager/{slash_output.go,slash_output_test.go,agent_switching.go,agent_switching_test.go}` |
| 10 | `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`, `TERMINAL.md`, `CHANGELOG.md` |

---

### Task 1: The per-row `wrapped` export, `logicalLines`, and copy that joins a logical line

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/grid.rs` (`ExportedRow.wrapped`, `GridSnapshot.row_wrapped`, `row_wrapped()`, `SnapshotCtx::push`, `export_history_row`, `export_screen_row`)
- Modify: `packages/terminal/crates/vt-core/src/lib.rs` (nothing but a recompile; `export_history_rows`/`export_screen_rows` already call the two exporters)
- Create: `packages/terminal/crates/vt-core/tests/logical_lines.rs`
- Modify: `packages/terminal/crates/vt-core/tests/common/mod.rs` (`check` verifies `row_wrapped.len()`)
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (`row_wrapped: Vec<u8>` through `refresh`, `apply`, `drop_front`, `rewrite_history_from`, `truncate_screen`, `push_row`, `compact`, getter), `packages/terminal/crates/vt-wasm/src/lib.rs` (`row_wrapped_ptr/len`)
- Modify: `packages/terminal/crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`
- Create: `packages/terminal/ts/core/src/logical-lines.ts`, `packages/terminal/ts/core/src/logical-lines.test.ts`
- Modify: `packages/terminal/ts/core/src/{types.ts,terminal-core.ts,terminal-core.test.ts,index-browser.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{selection-text.ts,selection-text.test.ts,selection-view.ts,terminal-selection.test.ts}`
- Modify: `frontend/src/renderer/test/setup.ts:56-64` only if `tsc` demands the new field on the fake snapshot
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `RowRange.wrapped` (`crates/vt-core/src/row_index.rs:12`), `ScreenGrid::row_wrapped(row)` (`screen.rs:184`), `ExportBuffers`'s dead/history accounting (`export.rs` `drop_front`/`compact`), `TextRows` (`selection-text.ts:4-10`), `snapshotTextRows` (`selection-view.ts:29`).
- Produces: the "Per-row wrapped" shapes above. Tasks 6, 7 and 8 read `TextRows.rowWrapped` through `logicalLineAt`; Task 10 closes the `TERMINAL.md` §5 gap.

The rule for the flag: `row_wrapped[i]` is true when row `i + 1` is a continuation of row `i` — the printer soft-wrapped off row `i` (`screen.rs:426`) or the rewrap cut a line there (`row_index.rs:368`). It is the meaning `RowIndex::rewrap` already uses when it walks back over `completed[index - 1].wrapped` (`row_index.rs:218`), and WezTerm's `last_cell_was_wrapped` (`wezterm-surface/src/line/line.rs:214`).

- [ ] **Step 1: Write the failing Rust tests**

`packages/terminal/crates/vt-core/tests/logical_lines.rs`:

```rust
mod common;

use vt_core::TerminalCore;

fn rows_and_flags(core: &TerminalCore) -> Vec<(String, bool)> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    (0..snapshot.row_count())
        .map(|index| (snapshot.row_text(index).to_string(), snapshot.row_wrapped(index)))
        .collect()
}

#[test]
fn a_soft_wrapped_screen_row_is_flagged_and_keeps_its_break_space() {
    let mut core = TerminalCore::new(4, 100).expect("core");
    core.resize(4, 3);
    core.feed(b"abc def");
    let rows = rows_and_flags(&core);
    assert_eq!(rows[0], ("abc ".to_string(), true));
    assert_eq!(rows[1], ("def".to_string(), false));
}

#[test]
fn a_hard_newline_is_not_a_wrap() {
    let mut core = TerminalCore::new(10, 100).expect("core");
    core.resize(10, 3);
    core.feed(b"one\r\ntwo");
    let rows = rows_and_flags(&core);
    assert_eq!(rows[0], ("one".to_string(), false));
    assert_eq!(rows[1], ("two".to_string(), false));
}

#[test]
fn a_wrapped_row_keeps_its_flag_when_it_is_evicted_into_scrollback() {
    let mut core = TerminalCore::new(4, 100).expect("core");
    core.resize(4, 2);
    core.feed(b"abc def\r\nx\r\ny\r\n");
    let rows = rows_and_flags(&core);
    let history = core.snapshot().expect("snapshot").history_rows as usize;
    assert!(history >= 2, "the wrapped pair is in scrollback");
    assert_eq!(rows[0], ("abc ".to_string(), true));
    assert_eq!(rows[1], ("def".to_string(), false));
}

#[test]
fn a_rewrap_cut_flags_every_piece_but_the_last() {
    let mut core = TerminalCore::new(40, 100).expect("core");
    core.resize(40, 2);
    core.feed(b"alpha beta gamma delta epsilon zeta\r\nx\r\ny\r\n");
    core.resize(12, 2);
    let rows = rows_and_flags(&core);
    let pieces: Vec<&(String, bool)> = rows.iter().take_while(|(text, _)| text != "x").collect();
    assert!(pieces.len() >= 3, "{pieces:?}");
    for piece in &pieces[..pieces.len() - 1] {
        assert!(piece.1, "{piece:?} is not the last piece and must be flagged");
    }
    assert!(!pieces[pieces.len() - 1].1, "the last piece is not flagged");
    let joined: String = pieces.iter().map(|(text, _)| text.as_str()).collect();
    assert_eq!(joined, "alpha beta gamma delta epsilon zeta");
}
```

Replace the body of `pub fn check` in `packages/terminal/crates/vt-core/tests/common/mod.rs` with:

```rust
pub fn check(core: &TerminalCore) {
    if let Err(error) = core.verify_integrity() {
        panic!("integrity violated: {error:?}");
    }
    let snapshot = core.snapshot().expect("snapshot builds");
    assert_eq!(snapshot.row_wrapped.len(), snapshot.row_count(), "one wrapped flag per row");
    for row in 0..snapshot.row_count() {
        let len = snapshot.row_text(row).len() as u32;
        let mut previous_end = 0u32;
        for span in snapshot.row_cell_spans(row) {
            assert!(span.start >= previous_end && span.start < span.end && span.end <= len, "row {row} span {span:?} outside {len} bytes or out of order");
            assert!(span.width <= 2, "row {row} span {span:?} width");
            previous_end = span.end;
        }
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test logical_lines` → compile error: no field `row_wrapped`, no method `row_wrapped`.

- [ ] **Step 3: Implement in `grid.rs`**

`ExportedRow` gains `pub wrapped: bool` (the only two literals are `export_history_row` at `grid.rs:314` and `export_screen_row` at `grid.rs:362`). `GridSnapshot` gains `pub row_wrapped: Vec<bool>` and

```rust
    pub fn row_wrapped(&self, index: usize) -> bool {
        self.row_wrapped[index]
    }
```

`build_snapshot` allocates `let mut row_wrapped: Vec<bool> = Vec::new();`, hands `row_wrapped: &mut row_wrapped` to `SnapshotCtx` (new field `row_wrapped: &'a mut Vec<bool>`), and puts `row_wrapped` into the returned struct after `row_indents`. `SnapshotCtx::push` adds `self.row_wrapped.push(row.wrapped);` right after `self.row_indents.push(row.indent);`.

`export_history_row`: `wrapped: row.wrapped` in the returned `ExportedRow`.

`export_screen_row` — replace the `width` computation and set the flag:

```rust
    let wrapped = screen.row_wrapped(row);
    let width = if wrapped {
        screen.cols()
    } else {
        (0..screen.cols())
            .rposition(|col| !screen.cell(row, col).is_blank())
            .map_or(0, |col| col + 1)
    };
```

and `wrapped,` in the returned `ExportedRow` (the `'\0'` spacer skip already handles a wide cell at the edge; `scrollback::commit_row` keeps the same full width for a wrapped row, `scrollback.rs:14-20`, so a screen row and its committed form now export the same bytes).

No other `ExportedRow` literal exists in the tree; if the compiler names one, give it the flag the row's source has.

Run: `cargo test -p vt-core` → PASS. `a_soft_wrapped_screen_row_is_flagged_and_keeps_its_break_space` is the test that pins the trailing blank; if it fails on `"abc "` vs `"abc"`, the `width` change above did not land.

- [ ] **Step 4: Write the failing vt-wasm tests**

`crates/vt-wasm/tests/export_layout.rs` — add:

```rust
#[test]
fn exports_one_wrapped_byte_per_row() {
    let mut core = TerminalCore::new(4, 10).unwrap();
    core.feed(b"abc def\r\nx");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.row_wrapped().len(), buffers.rows().len() / 2);
    assert_eq!(&buffers.row_wrapped()[..3], &[1, 0, 0]);
}
```

`crates/vt-wasm/tests/incremental_export.rs`: in `assert_bytes_equal` add `assert_eq!(incremental.row_wrapped(), full.row_wrapped());`, and extend `projected_rows` to carry the flag — change its return type to `Vec<(Vec<u8>, u16, bool, Vec<u32>)>`, read `let wrapped = buffers.row_wrapped();` beside `indents`, and push `wrapped[row] == 1` as the third tuple element. Add to the `op()` strategy: `2 => Just(Op::Bytes(b"abcd efgh ijkl".to_vec())),` (a line that soft-wraps at the small widths the `Resize` arm produces). `exit_encoding.rs`: the `GridSnapshot` literal gains `row_wrapped: Vec::new(),`.

Run: `cargo test -p vt-wasm` → compile error on `row_wrapped()`.

- [ ] **Step 5: Implement the export buffer**

`export.rs`: field `row_wrapped: Vec<u8>` after `row_indents`. Mirror `row_indents` at every site:

- `refresh`: `self.row_wrapped.clear();` beside the other clears; after `self.row_indents.extend_from_slice(&snapshot.row_indents);` add `self.row_wrapped.extend(snapshot.row_wrapped.iter().map(|&w| u8::from(w)));`.
- `rewrite_history_from`: `self.row_wrapped.truncate(cut_row);` beside `self.row_indents.truncate(cut_row);`.
- `truncate_screen`: `self.row_wrapped.truncate(keep_rows);`.
- `push_row`: `self.row_wrapped.push(u8::from(row.wrapped));` after `self.row_indents.push(row.indent);`.
- `compact`: `self.row_wrapped.drain(..self.dead_rows);` beside the `row_indents` drain.
- Getter: `pub fn row_wrapped(&self) -> &[u8] { &self.row_wrapped[self.dead_rows..] }`.

(`drop_front` only moves counters; nothing to add.) `lib.rs` (vt-wasm), after `row_indents_len`:

```rust
    pub fn row_wrapped_ptr(&self) -> *const u8 {
        self.export.row_wrapped().as_ptr()
    }

    pub fn row_wrapped_len(&self) -> usize {
        self.export.row_wrapped().len()
    }
```

Run: `cargo test -p vt-wasm` → PASS (the proptest is the incremental-vs-full guard; a mismatch means one of the sites above was missed).

- [ ] **Step 6: Write the failing TS tests**

`packages/terminal/ts/core/src/logical-lines.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { joinLogicalLine } from "./logical-lines";

describe("joinLogicalLine", () => {
	it("joins the pieces verbatim and records where each row starts", () => {
		expect(joinLogicalLine(["abc ", "def"])).toEqual({ text: "abc def", rowOffsets: [0, 4] });
		expect(joinLogicalLine(["漢字", "x"])).toEqual({ text: "漢字x", rowOffsets: [0, 2] });
		expect(joinLogicalLine(["only"])).toEqual({ text: "only", rowOffsets: [0] });
	});
});
```

Add to `packages/terminal/ts/core/src/terminal-core.test.ts` (inside the top-level `describe`):

```ts
	it("exports one wrapped byte per row and joins logical lines from it", () => {
		const core = createTerminalCore({ columns: 4, scrollback: 100 });
		core.resize(4, 3);
		core.feed(new TextEncoder().encode("abc def\r\nxy"));
		const snapshot = core.snapshot();
		expect(snapshot.rowWrapped.length).toBe(snapshot.rows.length / 2);
		expect([...snapshot.rowWrapped.subarray(0, 3)]).toEqual([1, 0, 0]);
		expect(core.logicalLines({ start: 1, end: 2 })).toEqual([
			{ firstRow: 0, rowCount: 2, text: "abc def", rowOffsets: [0, 4] },
		]);
		expect(core.logicalLines({ start: 0, end: 3 })).toEqual([
			{ firstRow: 0, rowCount: 2, text: "abc def", rowOffsets: [0, 4] },
			{ firstRow: 2, rowCount: 1, text: "xy", rowOffsets: [0] },
		]);
	});
```

`packages/terminal/ts/renderer-dom/src/selection-text.test.ts` — add `rowWrapped` to the three `TextRows` literals (`rows`, `trimmed`, `shifted`): `rowWrapped: () => false,` — and a fourth fixture plus two tests:

```ts
const wrappedRows: TextRows = {
	blockIds: ["w"],
	firstRow: () => 0,
	rowCount: () => 3,
	rowText: (_id, row) => ["abc ", "def", "tail"][row] ?? "",
	rowSpans: () => [],
	rowWrapped: (_id, row) => row === 0,
};

describe("selectedText over logical lines", () => {
	it("joins a wrapped row with the next one and keeps the break space", () => {
		expect(selectedText({ start: { blockId: "w", row: 0, cell: 0 }, end: { blockId: "w", row: 2, cell: ROW_END } }, wrappedRows)).toBe("abc def\ntail");
	});
	it("still trims the trailing spaces of the last row of a line", () => {
		const trailing: TextRows = { ...wrappedRows, rowText: (_id, row) => ["abc ", "def   ", "tail"][row] ?? "" };
		expect(selectedText({ start: { blockId: "w", row: 0, cell: 0 }, end: { blockId: "w", row: 1, cell: ROW_END } }, trailing)).toBe("abc def");
	});
});
```

Add to `packages/terminal/ts/renderer-dom/src/terminal-selection.test.ts` (it mounts a real core; use its existing helpers to feed and select — the file's own `mountWith`/drag helpers):

```ts
	it("copies a soft-wrapped line as one line", async () => {
		const { core, renderer } = mountWith("");
		core.resize(4, 3);
		feed(core, "abc def\r\n");
		await flushRepaint();
		renderer.selectionBegin({ blockId: "0:0", row: 0, column: 0, side: "left" }, "simple");
		renderer.selectionUpdate({ blockId: "0:0", row: 1, column: 2, side: "right" });
		expect(renderer.selectedText()).toBe("abc def");
	});
```

(If `terminal-selection.test.ts` names its helpers differently, use those names; the assertion is what matters.)

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/core && npx vitest run src/logical-lines.test.ts` → FAIL, module not found. `npx vitest run src/terminal-core.test.ts -t "wrapped byte"` → FAIL, `rowWrapped` undefined.

- [ ] **Step 7: Implement `logical-lines.ts`, the snapshot field, `logicalLines`, and the copy join**

`packages/terminal/ts/core/src/logical-lines.ts`:

```ts
import type { RowRange, TerminalSnapshot } from "./types.js";

export type LogicalLine = Readonly<{ firstRow: number; rowCount: number; text: string; rowOffsets: readonly number[] }>;

export function joinLogicalLine(texts: readonly string[]): { text: string; rowOffsets: number[] } {
	const rowOffsets: number[] = [];
	let text = "";
	for (const piece of texts) {
		rowOffsets.push(text.length);
		text += piece;
	}
	return { text, rowOffsets };
}

export function snapshotLogicalLines(snapshot: TerminalSnapshot, range: RowRange, decoder: TextDecoder): LogicalLine[] {
	const rowCount = snapshot.rows.length / 2;
	const wrapped = (row: number): boolean => row >= 0 && row + 1 < rowCount && snapshot.rowWrapped[row] === 1;
	const rowText = (row: number): string => {
		const start = snapshot.rows[row * 2] ?? 0;
		const end = snapshot.rows[row * 2 + 1] ?? start;
		return end > start ? decoder.decode(snapshot.content.subarray(start, end)) : "";
	};
	let first = Math.min(Math.max(range.start, 0), rowCount);
	while (first > 0 && wrapped(first - 1)) first -= 1;
	const stop = Math.min(range.end, rowCount);
	const lines: LogicalLine[] = [];
	let row = first;
	while (row < stop) {
		let last = row;
		while (wrapped(last)) last += 1;
		const texts: string[] = [];
		for (let index = row; index <= last; index += 1) texts.push(rowText(index));
		const { text, rowOffsets } = joinLogicalLine(texts);
		lines.push({ firstRow: row, rowCount: last - row + 1, text, rowOffsets });
		row = last + 1;
	}
	return lines;
}
```

`types.ts`: add `rowWrapped: Uint8Array;` to `TerminalSnapshot` after `rowIndents`. `terminal-core.ts` `buildSnapshot`: read `const rowWrappedPtr = this.inner.row_wrapped_ptr(); const rowWrappedLen = this.inner.row_wrapped_len();`, validate `if (rowWrappedLen * 2 !== rowsLen) throw new Error(`rowWrapped length ${rowWrappedLen} does not match ${rowsLen / 2} rows`);`, and add `rowWrapped: u8View(memory, rowWrappedPtr, rowWrappedLen),` after `rowIndents`. Add the method (after `snapshot()`), with `private readonly decoder = new TextDecoder("utf-8", { fatal: true });` as a field:

```ts
	logicalLines(range: RowRange): LogicalLine[] {
		validateRowRange(range);
		return snapshotLogicalLines(this.snapshot(), range, this.decoder);
	}
```

(import `validateRowRange` from `./types.js`, `snapshotLogicalLines`/`LogicalLine` from `./logical-lines.js`). `index-browser.ts`: `export { joinLogicalLine, type LogicalLine } from "./logical-lines.js";`.

`ts/renderer-dom/src/selection-text.ts`: `TextRows` gains `rowWrapped(blockId: string, row: number): boolean;`. Replace the inner row loop of `selectedText` so a wrapped row is concatenated verbatim to the next:

```ts
		let pending = "";
		for (let row = fromRow; row <= toRow; row += 1) {
			const from = index === first && row === range.start.row ? range.start.cell : 0;
			const to = index === last && row === range.end.row ? range.end.cell : ROW_END;
			const text = rows.rowText(blockId, row);
			const spans = rows.rowSpans(blockId, row);
			const joins = row < toRow && rows.rowWrapped(blockId, row);
			if (joins) {
				pending += to === ROW_END && from === 0 ? text : cellSlice(text, spans, from, to === ROW_END ? Number.MAX_SAFE_INTEGER : to);
				continue;
			}
			lines.push(pending + cut(text, spans, from, to));
			pending = "";
		}
		if (pending !== "") lines.push(pending.replace(/ +$/u, ""));
```

`ts/renderer-dom/src/selection-view.ts` `snapshotTextRows`: the alt branch gets `rowWrapped: () => false,`; the primary branch gets

```ts
		rowWrapped: (id, row) => {
			const block = byId.get(id);
			if (!block) return false;
			const flat = row - base;
			if (flat < block.firstRow || flat + 1 >= block.firstRow + block.rowCount) return false;
			return snapshot.rowWrapped[flat] === 1;
		},
```

(a wrap never crosses a block boundary: the last row of a block is never joined onward, which is what the `flat + 1 >=` test enforces).

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS. `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → if `test/setup.ts:56-64`'s fake snapshot fails the type check, add `rowWrapped: new Uint8Array(0),` beside its other arrays.

- [ ] **Step 8: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → PASS (`vt_host.wasm` embeds `vt-core`; `TestProcessEnvironmentLetsOverridesWin` is the pre-existing failure `TERMINAL.md` §5 names).
- `npm run bench:selection` → PASS (the copy path changed). `npm run bench:feel` → `PASS feel gate: zero pixel diff` (wrapped screen rows now export trailing spaces; spaces in a `pre` span paint nothing — this line is the proof).
- `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

CHANGELOG (under "Unreleased"):

```markdown
- vt-core/vt-wasm/core: the snapshot exports one `rowWrapped` byte per row (1 when the next row continues this one — a printer soft-wrap or a rewrap cut), through the incremental export like `rowIndents`; a soft-wrapped screen row now exports its trailing blanks the way `scrollback::commit_row` already committed them, so the break space survives the join. `TerminalCore.logicalLines(range)` joins the flagged rows (WezTerm `mux/src/pane.rs` `LogicalLine`).
- renderer-dom: copying a selection joins a soft-wrapped line into one line — the first `TERMINAL.md` §5 gap. The last row of a line is still trimmed of trailing spaces; a wrapped row is joined verbatim. Rows a reopened pane received as history are never flagged (`history.rs:193`), so a line the mirror wrapped before the reopen still copies as several lines.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/ts/core/src packages/terminal/ts/renderer-dom/src packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm frontend/src/renderer/test/setup.ts && git commit -m "vt-core: export the per-row wrapped flag; logical lines; copy joins a soft-wrapped line

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 2: OSC 8 hyperlinks in the core — registry, pen state, the sixth style word, the link table export (ONE commit)

**Files:**
- Create: `packages/terminal/crates/vt-core/src/hyperlink.rs`
- Modify: `packages/terminal/crates/vt-core/src/{lib.rs,style.rs,sgr.rs,parser.rs,grid.rs,screen/snapshot.rs}`
- Create: `packages/terminal/crates/vt-core/tests/osc8.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/{export.rs,lib.rs}`, `packages/terminal/crates/vt-wasm/tests/{exit_encoding.rs,export_layout.rs,incremental_export.rs}`
- Modify: `packages/terminal/crates/vt-host/src/lib.rs` only if it stops compiling (it constructs no `CellStyle` literal today; Task 3 changes it deliberately)
- Modify: `packages/terminal/ts/core/src/{style-runs.ts,types.ts,terminal-core.ts,terminal-core.test.ts,index-browser.ts}`
- Modify: the hand-built style arrays in `packages/terminal/ts/renderer-dom/src/{alt-surface.test.ts:51,attributes.test.ts:25,93,111,block-glyphs.test.ts:14,108,125,cursor.test.ts:116,width-cache.test.ts:29,59}` (each gains a sixth word `0`)
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `Parser::osc_dispatch` (`parser.rs:836`, a trace-only no-op), `pending_style` (`parser.rs:36`), `sgr::apply` (`sgr.rs:6`, resets to `CellStyle::DEFAULT` at lines 9 and 29), `STYLE_RUN_WORDS = 5` sites (`export.rs:16`, `style-runs.ts:1`, `row-builder.ts`, `cursor.ts`, `alt-surface.ts`), the `ExportedRow`/`ExportBuffers` layout from Task 1.
- Produces: the "Hyperlinks" shapes above. Task 3 makes the mirror re-emit them; Task 6 reads `stylePairs[i * STYLE_RUN_WORDS + STYLE_WORD_LINK]` and `TerminalCore.linkUri(id)`.

The OSC 8 wire form is `OSC 8 ; params ; URI ST`; vte hands `osc_dispatch` the `;`-split fields, so `params[0] == b"8"`, `params[1]` is the `key=value:key=value` params field (may be empty) and `params[2..]` is the URI, split again wherever it contained `;` — rejoin with `;` (Warp `control_sequence_parameters.rs:775-790`). An empty URI closes the link. The cap on the URI is checked on the raw byte length before any `String` is built, `MAX_URI_BYTES = 2083`; an `id=` over `MAX_ID_BYTES = 256` is dropped and the link kept; the registry refuses the 4097th distinct link and returns `None`, so those cells carry no link rather than a dangling id (`hyperlink_registry.rs:31,65-80`).

- [ ] **Step 1: Write the failing Rust tests**

`packages/terminal/crates/vt-core/tests/osc8.rs`:

```rust
mod common;

use vt_core::hyperlink::{parse_osc8, Hyperlink, HyperlinkRegistry, MAX_DISTINCT_ENTRIES, MAX_URI_BYTES};
use vt_core::{CellStyle, TerminalCore};

fn link_runs(core: &TerminalCore, row: usize) -> Vec<(u32, u16)> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    snapshot
        .row_style_pairs(row)
        .iter()
        .map(|(end, style)| (*end, style.link))
        .collect()
}

#[test]
fn cell_style_stays_sixteen_bytes_with_the_link_id() {
    assert_eq!(std::mem::size_of::<CellStyle>(), 16);
    assert_eq!(CellStyle::DEFAULT.link, 0);
}

#[test]
fn parse_osc8_reads_id_and_rejoins_a_uri_that_contained_semicolons() {
    let link = parse_osc8(&[b"id=abc", b"https://x.y/a", b"b=c"]).expect("open form");
    assert_eq!(link, Hyperlink { id: Some("abc".to_string()), uri: "https://x.y/a;b=c".to_string() });
    assert_eq!(parse_osc8(&[b"", b"https://x.y"]), Some(Hyperlink { id: None, uri: "https://x.y".to_string() }));
    assert_eq!(parse_osc8(&[b"", b""]), None);
    assert_eq!(parse_osc8(&[]), None);
    let long = vec![b'x'; MAX_URI_BYTES + 1];
    assert_eq!(parse_osc8(&[b"", long.as_slice()]), None);
    let big_id = vec![b'i'; 257];
    let mut params = b"id=".to_vec();
    params.extend_from_slice(&big_id);
    assert_eq!(parse_osc8(&[params.as_slice(), b"https://x.y"]), Some(Hyperlink { id: None, uri: "https://x.y".to_string() }));
}

#[test]
fn the_registry_dedupes_caps_and_never_reclaims() {
    let mut registry = HyperlinkRegistry::default();
    let a = registry.intern(Hyperlink { id: None, uri: "https://a".to_string() }).expect("a");
    let again = registry.intern(Hyperlink { id: None, uri: "https://a".to_string() }).expect("a again");
    assert_eq!(a, again);
    assert_eq!(a, 1);
    let with_id = registry.intern(Hyperlink { id: Some("k".to_string()), uri: "https://a".to_string() }).expect("a with id");
    assert_ne!(with_id, a);
    assert_eq!(registry.uri(a), Some("https://a"));
    assert_eq!(registry.uri(0), None);
    for n in registry.len()..MAX_DISTINCT_ENTRIES {
        assert!(registry.intern(Hyperlink { id: None, uri: format!("https://n/{n}") }).is_some());
    }
    assert_eq!(registry.len(), MAX_DISTINCT_ENTRIES);
    assert_eq!(registry.intern(Hyperlink { id: None, uri: "https://one-too-many".to_string() }), None);
    assert_eq!(registry.uri(a), Some("https://a"));
}

#[test]
fn printed_cells_carry_the_link_until_it_is_closed() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"pre \x1b]8;;https://x.y\x1b\\link\x1b]8;;\x1b\\ post");
    assert_eq!(link_runs(&core, 0), vec![(4, 0), (8, 1), (13, 0)]);
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.link_uri(1), Some("https://x.y"));
    assert_eq!(core.hyperlink_uri(1), Some("https://x.y"));
    assert_eq!(core.hyperlink_count(), 1);
}

#[test]
fn sgr_reset_keeps_the_link_and_a_new_osc8_replaces_it() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b]8;;https://a\x1b\\\x1b[31mred\x1b[0mplain\x1b]8;;https://b\x1b\\bee\x1b]8;;\x1b\\");
    assert_eq!(link_runs(&core, 0), vec![(3, 1), (8, 1), (11, 2)]);
}

#[test]
fn a_link_survives_eviction_and_rewrap_because_offsets_do_not_move() {
    let mut core = TerminalCore::new(12, 100).expect("core");
    core.resize(12, 2);
    core.feed(b"\x1b]8;;https://x.y/long\x1b\\alpha beta gamma\x1b]8;;\x1b\\\r\nx\r\ny\r\n");
    core.resize(6, 2);
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    let linked: Vec<String> = (0..snapshot.row_count())
        .filter(|row| snapshot.row_style_pairs(*row).iter().any(|(_, style)| style.link == 1))
        .map(|row| snapshot.row_text(row).to_string())
        .collect();
    assert_eq!(linked.concat(), "alpha beta gamma");
    assert_eq!(snapshot.link_uri(1), Some("https://x.y/long"));
}

#[test]
fn a_boundary_mark_drops_the_pen_link() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b]8;;https://x.y\x1b\\open\x1b]7000;v=1;boundary=0\x07after");
    let snapshot = core.snapshot().expect("snapshot");
    let after = (0..snapshot.row_count()).find(|row| snapshot.row_text(*row) == "after").expect("after row");
    assert!(snapshot.row_style_pairs(after).iter().all(|(_, style)| style.link == 0));
}

#[test]
fn the_alternate_screen_carries_links_through_the_same_registry() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b[?1049h\x1b]8;;https://alt\x1b\\alt\x1b]8;;\x1b\\");
    let snapshot = core.snapshot().expect("snapshot");
    let alt = snapshot.alt.expect("alt");
    assert_eq!(alt.style_pairs[0].1.link, 1);
    assert_eq!(snapshot.link_uri(1), Some("https://alt"));
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test osc8` → compile error: no module `hyperlink`, no field `link`.

- [ ] **Step 3: Implement the registry, the style field, the parser arm**

`packages/terminal/crates/vt-core/src/hyperlink.rs`:

```rust
use std::collections::HashMap;

// warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs (caps, no reclamation)
pub const MAX_DISTINCT_ENTRIES: usize = 4096;
// warp/crates/warp_terminal/src/model/ansi/control_sequence_parameters.rs:714,718
pub const MAX_URI_BYTES: usize = 2083;
pub const MAX_ID_BYTES: usize = 256;

pub type LinkId = u16;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Hyperlink {
    pub id: Option<String>,
    pub uri: String,
}

#[derive(Debug, Default)]
pub struct HyperlinkRegistry {
    by_link: HashMap<Hyperlink, LinkId>,
    by_id: Vec<Hyperlink>,
}

impl HyperlinkRegistry {
    pub fn intern(&mut self, link: Hyperlink) -> Option<LinkId> {
        if link.uri.len() > MAX_URI_BYTES {
            return None;
        }
        if let Some(&id) = self.by_link.get(&link) {
            return Some(id);
        }
        if self.by_id.len() >= MAX_DISTINCT_ENTRIES {
            return None;
        }
        let id = LinkId::try_from(self.by_id.len() + 1).ok()?;
        self.by_id.push(link.clone());
        self.by_link.insert(link, id);
        Some(id)
    }

    pub fn uri(&self, id: LinkId) -> Option<&str> {
        let index = usize::from(id).checked_sub(1)?;
        self.by_id.get(index).map(|link| link.uri.as_str())
    }

    pub fn len(&self) -> usize {
        self.by_id.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_id.is_empty()
    }
}

pub fn parse_osc8(params: &[&[u8]]) -> Option<Hyperlink> {
    let (params_field, uri_parts) = params.split_first()?;
    let uri_len = uri_parts.iter().map(|part| part.len()).sum::<usize>() + uri_parts.len().saturating_sub(1);
    if uri_len == 0 || uri_len > MAX_URI_BYTES {
        return None;
    }
    let mut uri_bytes = Vec::with_capacity(uri_len);
    for (index, part) in uri_parts.iter().enumerate() {
        if index > 0 {
            uri_bytes.push(b';');
        }
        uri_bytes.extend_from_slice(part);
    }
    let uri = String::from_utf8(uri_bytes).ok()?;
    let mut id = None;
    for pair in params_field.split(|byte| *byte == b':') {
        let Some(equals) = pair.iter().position(|byte| *byte == b'=') else {
            continue;
        };
        let (key, value) = (&pair[..equals], &pair[equals + 1..]);
        if key == b"id" && !value.is_empty() && value.len() <= MAX_ID_BYTES {
            if let Ok(value) = std::str::from_utf8(value) {
                id = Some(value.to_owned());
            }
        }
    }
    Some(Hyperlink { id, uri })
}
```

`lib.rs`: `pub mod hyperlink;` and `pub use hyperlink::{Hyperlink, HyperlinkRegistry, LinkId};`. `style.rs`: `CellStyle` gains `pub link: LinkId` (import `crate::hyperlink::LinkId`); `DEFAULT` sets `link: 0`; `new` sets `link: 0`; `resolved` copies `link: self.link`. `sgr.rs`: replace both `*style = CellStyle::DEFAULT;` (lines 9 and 29) with `*style = CellStyle { link: style.link, ..CellStyle::DEFAULT };`.

`parser.rs`: field `hyperlinks: HyperlinkRegistry` (initialised `HyperlinkRegistry::default()`), accessors

```rust
    pub fn hyperlinks(&self) -> &HyperlinkRegistry {
        &self.hyperlinks
    }

    pub(crate) fn hyperlinks_mut(&mut self) -> &mut HyperlinkRegistry {
        &mut self.hyperlinks
    }
```

and the `osc_dispatch` arm (keep the trace record; drop the `let _ = params;` since `params` is now read):

```rust
    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        #[cfg(feature = "trace")]
        self.trace.record(crate::trace::TraceAction::Osc(
            params.iter().map(|p| p.to_vec()).collect(),
        ));
        if params.first().copied() == Some(b"8".as_slice()) {
            let id = crate::hyperlink::parse_osc8(&params[1..])
                .and_then(|link| self.hyperlinks.intern(link));
            self.pending_style.link = id.unwrap_or(0);
        }
    }
```

`process_boundary` already resets `pending_style = CellStyle::DEFAULT` (link 0) — that is what `a_boundary_mark_drops_the_pen_link` pins.

`grid.rs`: `GridSnapshot` gains `pub link_text: Vec<u8>`, `pub link_ranges: Vec<(u32, u32)>` and

```rust
    pub fn link_uri(&self, id: crate::hyperlink::LinkId) -> Option<&str> {
        let (start, end) = *self.link_ranges.get(usize::from(id).checked_sub(1)?)?;
        std::str::from_utf8(&self.link_text[start as usize..end as usize]).ok()
    }
```

`build_snapshot` takes one more parameter `links: &HyperlinkRegistry` (after `width_mode`) and fills the two vectors:

```rust
    let mut link_text: Vec<u8> = Vec::new();
    let mut link_ranges: Vec<(u32, u32)> = Vec::with_capacity(links.len());
    for id in 1..=links.len() {
        let uri = links.uri(id as crate::hyperlink::LinkId).unwrap_or("");
        let start = checked_u32(link_text.len())?;
        link_text.extend_from_slice(uri.as_bytes());
        link_ranges.push((start, checked_u32(link_text.len())?));
    }
```

`lib.rs` `snapshot()` passes `self.parser.hyperlinks()`, and adds

```rust
    pub fn hyperlink_count(&self) -> usize {
        self.parser.hyperlinks().len()
    }

    pub fn hyperlink_uri(&self, id: LinkId) -> Option<&str> {
        self.parser.hyperlinks().uri(id)
    }
```

`screen/snapshot.rs` needs no change (it copies whole `CellStyle`s).

Run: `cargo test -p vt-core` → PASS. There is no `CellStyle { … }` literal outside `style.rs` today (every other site uses `::DEFAULT`, `::new` or `::from_fg`), so the three constructors above are the whole change; if the compiler names another literal, give it `link: 0`.

- [ ] **Step 4: Write the failing vt-wasm tests**

`crates/vt-wasm/tests/export_layout.rs`: the assertion in `flattens_rows_and_runs_as_u32_pairs` becomes six words per run:

```rust
    assert_eq!(
        buffers.style_pairs(),
        &[3, 1, 254, 0, 255, 0, 6, 255, 254, 0, 255, 0, 5, 255, 254, 0, 255, 0]
    );
```

and add:

```rust
#[test]
fn exports_the_link_id_as_the_sixth_word_and_the_uri_table_beside_it() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed(b"a\x1b]8;;https://x.y\x1b\\b\x1b]8;;\x1b\\c");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot().unwrap()).unwrap();

    assert_eq!(buffers.style_pairs(), &[1, 255, 254, 0, 255, 0, 2, 255, 254, 0, 255, 1, 3, 255, 254, 0, 255, 0]);
    assert_eq!(buffers.link_text(), b"https://x.y");
    assert_eq!(buffers.link_ranges(), &[0, 11]);
}

#[test]
fn a_partial_delta_appends_new_links_without_rebuilding_the_table() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.resize(16, 2);
    let mut buffers = ExportBuffers::default();
    let initial = core.take_delta();
    buffers.apply(&core, &initial).unwrap();
    core.feed(b"\x1b]8;;https://one\x1b\\1\x1b]8;;\x1b\\\r\n");
    let first = core.take_delta();
    assert_eq!(first.kind, vt_core::DeltaKind::Partial);
    buffers.apply(&core, &first).unwrap();
    core.feed(b"\x1b]8;;https://two\x1b\\2\x1b]8;;\x1b\\\r\n");
    let second = core.take_delta();
    assert_eq!(second.kind, vt_core::DeltaKind::Partial);
    buffers.apply(&core, &second).unwrap();

    assert_eq!(buffers.link_text(), b"https://onehttps://two");
    assert_eq!(buffers.link_ranges(), &[0, 11, 11, 22]);
}
```

`incremental_export.rs`: add `assert_eq!(incremental.link_text(), full.link_text()); assert_eq!(incremental.link_ranges(), full.link_ranges());` to `assert_bytes_equal`, and to the `op()` strategy `2 => "[a-z]{1,8}".prop_map(|host| Op::Bytes(format!("\x1b]8;;https://{host}\x1b\\lk\x1b]8;;\x1b\\").into_bytes())),`. `exit_encoding.rs`: the `GridSnapshot` literal gains `link_text: Vec::new(), link_ranges: Vec::new(),`.

Run: `cargo test -p vt-wasm` → compile error on `link_text()` and the six-word arrays.

- [ ] **Step 5: Implement the export**

`export.rs`: `pub const STYLE_RUN_WORDS: usize = 6;`. Fields `link_text: Vec<u8>`, `link_ranges: Vec<u32>`, `links_exported: usize`. Every place a style is pushed (`refresh` primary and alt, `push_row`) gains `self.<vec>.push(u32::from(style.link));` as the sixth push. `refresh`: clear the two link vectors, then

```rust
        for &(start, end) in &snapshot.link_ranges {
            self.link_ranges.push(start);
            self.link_ranges.push(end);
        }
        self.link_text.extend_from_slice(&snapshot.link_text);
        self.links_exported = snapshot.link_ranges.len();
```

`apply` (partial path), after `write_blocks`:

```rust
        for id in (self.links_exported + 1)..=core.hyperlink_count() {
            let uri = core.hyperlink_uri(id as u16).unwrap_or("");
            let start = checked_u32_from_u64(self.link_text.len() as u64)?;
            self.link_text.extend_from_slice(uri.as_bytes());
            self.link_ranges.push(start);
            self.link_ranges.push(checked_u32_from_u64(self.link_text.len() as u64)?);
        }
        self.links_exported = core.hyperlink_count();
```

Getters `pub fn link_text(&self) -> &[u8]` and `pub fn link_ranges(&self) -> &[u32]`. (`compact` does not touch the link table: the registry never reclaims, so neither does the export.) `lib.rs` (vt-wasm): four getters `link_text_ptr/len` (`*const u8`) and `link_ranges_ptr/len` (`*const u32`) shaped like `block_text_ptr/len` and `run_ranges_ptr/len`.

Run: `cargo test -p vt-wasm` → PASS.

- [ ] **Step 6: TS — the stride, the table, `linkUri`, the test arrays**

`ts/core/src/style-runs.ts`: `export const STYLE_RUN_WORDS = 6;` and `export const STYLE_WORD_LINK = 5;`. `index-browser.ts`: export `STYLE_WORD_LINK` beside `STYLE_RUN_WORDS`. `types.ts`: `linkRanges: Uint32Array; linkText: Uint8Array;` on `TerminalSnapshot` after `blockText`. `terminal-core.ts` `buildSnapshot`: read `link_ranges_ptr/len` and `link_text_ptr/len`, `validateEvenLength("linkRanges", linkRangesLen)`, add both views. Add to `TerminalCore`:

```ts
	private readonly linkUris = new Map<number, string>();

	linkUri(id: number): string | null {
		if (!Number.isInteger(id) || id <= 0) return null;
		const hit = this.linkUris.get(id);
		if (hit !== undefined) return hit;
		const snapshot = this.snapshot();
		const start = snapshot.linkRanges[(id - 1) * 2];
		const end = snapshot.linkRanges[(id - 1) * 2 + 1];
		if (start === undefined || end === undefined) return null;
		const uri = this.decoder.decode(snapshot.linkText.subarray(start, end));
		this.linkUris.set(id, uri);
		return uri;
	}
```

(`dispose()` clears `linkUris`; `decoder` is the field Task 1 added.) `terminal-core.test.ts`: the six-word expectation

```ts
		expect([...snapshot.stylePairs]).toEqual([3, 1, 254, 0, 255, 0, 9, 255, 254, 0, 255, 0, 5, 255, 254, 0, 255, 0]);
```

(the existing five-word line at :25) and a new test:

```ts
	it("exports the link id in the sixth style word and resolves the uri", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 10 });
		core.feed(new TextEncoder().encode("a\x1b]8;;https://x.y\x1b\\b\x1b]8;;\x1b\\c"));
		const snapshot = core.snapshot();
		expect(snapshot.stylePairs[1 * STYLE_RUN_WORDS + STYLE_WORD_LINK]).toBe(1);
		expect(core.linkUri(1)).toBe("https://x.y");
		expect(core.linkUri(2)).toBeNull();
		expect(core.linkUri(0)).toBeNull();
	});
```

Then every hand-built style array listed under **Files** gains a trailing `0` (the link word): `alt-surface.test.ts:51` (its `stylePairs` source array — every run), `attributes.test.ts:25,93,111`, `block-glyphs.test.ts:14,108,125`, `cursor.test.ts:116`, `width-cache.test.ts:29,59`. `row-builder.ts`, `cursor.ts` and `alt-surface.ts` index by `STYLE_RUN_WORDS` and need no change.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS. A renderer test that still passes a five-word array fails with a shifted run end — the list above is what to fix, nothing in `src/*.ts` proper.

- [ ] **Step 7: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → PASS.
- `npm run bench:selection` → PASS. `npm run bench:feel` → `PASS feel gate: zero pixel diff` (neither fixture emits OSC 8; the stride change moves no pixel). `npm run bench:agent:gate` → PASS; note the `rendererMemoryBytes` line for Task 10.
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean. `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

CHANGELOG:

```markdown
- vt-core/vt-wasm/core: `OSC 8 ; params ; URI ST` is parsed in `Parser::osc_dispatch` and interned per core in a `HyperlinkRegistry` with Warp's two rules (`warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs`): at most `MAX_DISTINCT_ENTRIES = 4096` distinct links, URIs over `MAX_URI_BYTES = 2083` refused, entries never reclaimed. `CellStyle` gains `link: u16` (0 = none; SGR 0 keeps it, a process boundary drops it) in the padding after `attrs`, so it stays 16 bytes; the style run grows to six words `(end, fg, bg, attrs, underline, link)` — `STYLE_RUN_WORDS = 6`, `STYLE_WORD_LINK = 5` — and the snapshot exports the URI table as `linkRanges`/`linkText`, appended incrementally. `TerminalCore.linkUri(id)` resolves an id. The table is outside `Limits { bytes }` — `trim_to` and `memory_stats` weigh content plus styles only — so a core can hold up to ~8.5 MB of interned URIs above its budget for its lifetime; the two caps are what bounds it. Nothing paints or opens a link yet.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/ts/core/src packages/terminal/ts/renderer-dom/src packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: OSC 8 hyperlinks interned per core, link id as the sixth style word, uri table export

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 3: The mirror re-emits OSC 8 in the replay and history; the history receiver interns it

**Files:**
- Modify: `packages/terminal/crates/vt-host/src/lib.rs` (`write_styled_row`, `write_styled_row_with` gain a URI lookup; the callers at `:264`, `:272`, `:331`, `:385`, `:476` pass `|id| snapshot.link_uri(id)`)
- Modify: `packages/terminal/crates/vt-core/src/history.rs` (`ScreenPerform.links`, `osc_dispatch` arm, `HistoryReceiver::consume(bytes, links)`), `packages/terminal/crates/vt-core/src/lib.rs` (`feed_raw` passes `self.parser.hyperlinks_mut()`)
- Modify: `packages/terminal/crates/vt-core/tests/osc8.rs`
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`, `backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `GridSnapshot::link_uri` (Task 2), `write_styled_row_with` (`vt-host/src/lib.rs:581`), `HistoryReceiver::consume` (`history.rs:66`), `Parser::hyperlinks_mut` (Task 2).
- Produces: a replay / history stream in which every linked run is bracketed by `ESC ] 8 ; ; <uri> ESC \` … `ESC ] 8 ; ; ESC \`; a reopened pane whose history rows carry link ids of its own registry.

Without this, a pane reopened after Task 2 would show links only for rows produced after the reopen: the mirror's registry is not the client's, so ids cannot travel — the URI has to. Emitting the sequence per run (not once per link) keeps `write_styled_row_with` stateless, which is what `clip_row`'s clipping and the chunk framing rely on.

- [ ] **Step 1: Write the failing tests**

Add to `packages/terminal/crates/vt-core/tests/osc8.rs`:

```rust
#[test]
fn a_history_chunk_carrying_osc8_interns_into_the_receiving_core() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b]8;;https://old\x1b\\older\x1b]8;;\x1b\\\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    assert_eq!(snapshot.row_text(0), "older");
    let link = snapshot.row_style_pairs(0)[0].1.link;
    assert_ne!(link, 0);
    assert_eq!(snapshot.link_uri(link), Some("https://old"));
}
```

Add to `backend/internal/adapters/runtime/ptyhost/vtwasm/replay_test.go`:

```go
func TestReplayBracketsALinkedRunWithOsc8(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "see \x1b]8;;https://x.y/doc\x1b\\here\x1b]8;;\x1b\\ now\r\n")

	out, err := p.Replay(1000)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	want := "\x1b]8;;https://x.y/doc\x1b\\"
	if !strings.Contains(out, want+"here") {
		t.Fatalf("replay lost the hyperlink open before its run:\n%q", out)
	}
	if !strings.Contains(out, "here\x1b[0m\x1b]8;;\x1b\\") && !strings.Contains(out, "here\x1b]8;;\x1b\\") {
		t.Fatalf("replay lost the hyperlink close after its run:\n%q", out)
	}
	if strings.Count(out, "\x1b]8;;") != 2 {
		t.Fatalf("expected exactly one open and one close, got %d in:\n%q", strings.Count(out, "\x1b]8;;"), out)
	}
}

func TestHistoryChunksCarryOsc8(t *testing.T) {
	p := newTestParser(t, 20, 2)
	feed(t, p, "\x1b]8;;https://old\x1b\\older\x1b]8;;\x1b\\\r\nx\r\ny\r\nz\r\n")

	chunk, _, _, err := p.HistoryChunk(HistoryBefore, 1000, 512)
	if err != nil {
		t.Fatalf("history chunk: %v", err)
	}
	if !strings.Contains(chunk, "\x1b]8;;https://old\x1b\\older") {
		t.Fatalf("history chunk lost the hyperlink:\n%q", chunk)
	}
}
```

(`HistoryBefore` is the sentinel `TERMINAL.md` §4.21 names; if `vtwasm.go` spells it differently, use that name — `grep -n "HistoryBefore" backend/internal/adapters/runtime/ptyhost/vtwasm/*.go`.)

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test osc8 a_history_chunk` → FAIL: `link` is 0 (the receiver's `ScreenPerform` has no OSC arm). `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/vtwasm/ -run 'TestReplayBracketsALinkedRunWithOsc8|TestHistoryChunksCarryOsc8'` → FAIL: no `]8;;` in the output (the Go test runs the committed `vt_host.wasm`, which is still Task 2's).

- [ ] **Step 3: Implement**

`history.rs`: `ScreenPerform` gains `links: &'a mut HyperlinkRegistry` (import `crate::hyperlink::HyperlinkRegistry`); `consume` becomes `pub fn consume(&mut self, bytes: &[u8], links: &mut HyperlinkRegistry) -> usize` and builds `ScreenPerform { screen, style: &mut self.pending_style, links }`; add to the `impl Perform for ScreenPerform`:

```rust
    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if params.first().copied() == Some(b"8".as_slice()) {
            let id = crate::hyperlink::parse_osc8(&params[1..]).and_then(|link| self.links.intern(link));
            self.style.link = id.unwrap_or(0);
        }
    }
```

`lib.rs` `feed_raw`: both `self.history.consume(bytes)` calls become `self.history.consume(bytes, self.parser.hyperlinks_mut())` (the borrow is fine: `history` and `parser` are separate fields).

`vt-host/src/lib.rs`: `write_styled_row(text, row_bytes, pairs, link_uri: &dyn Fn(u16) -> Option<&str>)` and `write_styled_row_with(text, row_bytes, pairs, link_uri, terminator)`; inside the run loop, after the SGR is written and before the run text:

```rust
        let uri = if style.link == 0 { None } else { link_uri(style.link) };
        if let Some(uri) = uri {
            text.push_str("\x1b]8;;");
            text.push_str(uri);
            text.push_str("\x1b\\");
        }
        text.push_str(std::str::from_utf8(&row_bytes[start..end]).unwrap_or(""));
        if uri.is_some() {
            text.push_str("\x1b]8;;\x1b\\");
        }
```

Every caller passes `&|id| snapshot.link_uri(id)` (the alt branches at `:264` and `:331` have the primary `snapshot` in scope; alt links are in the same registry).

Run: `cargo test -p vt-core --test osc8` → PASS; `cargo test` → PASS.

- [ ] **Step 4: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → the two new tests PASS, `TestReplayKeepsSgrAttributesAndTheUnderlineColour` still PASS.
- `npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff`.
- `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

CHANGELOG:

```markdown
- vt-host/vt-core: the attach replay, `vt_render_styled` and every history chunk bracket a linked run with `OSC 8 ;; <uri> ST` … `OSC 8 ;; ST`, and a reopened pane's history receiver interns those into its own registry, so links survive a reattach and a reopen like colours do.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm && git commit -m "vt-host: replay and history chunks carry OSC 8; the history receiver interns links

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 4: Block timestamps from the `feed_at` clock, `startedAtMs`/`finishedAtMs` on `BlockView`, `onBlockFinished`

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/block.rs` (`BlockRecord.started_at_ms`, `finished_at_ms`), `block_grid.rs` (`clock_ms`, `trailing_started_at_ms`, `set_clock`, `note_output`, `open_block`/`close_block`/`push_synthetic` fallbacks), `parser.rs` (`set_clock`, `note_output`), `lib.rs` (`feed_raw` sets the clock and notes output), `grid.rs` (`export_blocks` fills the two fields, the synthetic records read `trailing_started_at_ms`)
- Create: `packages/terminal/crates/vt-core/tests/block_timestamps.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/export.rs` (`BLOCK_RECORD_WORDS = 18`, four more words), `packages/terminal/crates/vt-wasm/tests/exit_encoding.rs` (`record()` gains the fields; a new test for the four words)
- Modify: `packages/terminal/ts/core/src/{blocks.ts,types.ts,terminal-core.ts,block-contract.test.ts,terminal-core.test.ts}`
- Create: `packages/terminal/ts/renderer-dom/src/block-finished.ts`, `packages/terminal/ts/renderer-dom/src/block-finished.test.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts,index.ts}`
- Modify: `packages/terminal/ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `BlockMeta.started_at_ms`/`finished_at_ms` (`block.rs:47-48`, set by `set_meta_field` `block_grid.rs:221-284` from the hook's `start_ms`/`end_ms`), `TerminalCore::feed_at` (`lib.rs:125`, stores `now_ms`), `export_blocks` (`grid.rs`, builds `duration_ms` from the two), `BlockGrid::{open_block, close_block, push_synthetic}` (`block_grid.rs:107,137,184`), `decodeBlocks` (`blocks.ts`), `headerKeyOf` (`block-body.ts`), `repaint` decoding blocks (`dom-block-renderer.ts`).
- Produces: the "Block timestamps" shapes above. Task 9 subscribes to `onBlockFinished` in Operator.

There is one timestamp mechanism: `BlockMeta.started_at_ms`/`finished_at_ms`. The hook's values win when present; the fallback fills a missing one from the clock the core was last fed with. A Claude Code pane has no hook, so its blocks are synthetic: the running trailing block starts at the first feed after the previous block closed and finishes at the process boundary that closes it.

- [ ] **Step 1: Write the failing Rust tests**

`packages/terminal/crates/vt-core/tests/block_timestamps.rs`:

```rust
mod common;

use vt_core::{BlockRecord, BlockState, TerminalCore};

fn records(core: &TerminalCore) -> Vec<BlockRecord> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    snapshot.blocks
}

#[test]
fn a_block_without_hook_timestamps_gets_the_feed_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n", 1_000);
    core.feed_at(b"\x1b]133;D;0\x07", 4_500);
    let blocks = records(&core);
    let block = blocks.iter().find(|b| b.state == BlockState::Finished).expect("finished block");
    assert_eq!(block.started_at_ms, Some(1_000));
    assert_eq!(block.finished_at_ms, Some(4_500));
    assert_eq!(block.duration_ms, Some(3_500));
}

#[test]
fn hook_timestamps_win_over_the_fallback() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]7000;v=1;start_ms=500\x07\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n", 1_000);
    core.feed_at(b"\x1b]7000;v=1;end_ms=2000\x07\x1b]133;D;0\x07", 4_500);
    let blocks = records(&core);
    let block = blocks.iter().find(|b| b.state == BlockState::Finished).expect("finished block");
    assert_eq!(block.started_at_ms, Some(500));
    assert_eq!(block.finished_at_ms, Some(2_000));
    assert_eq!(block.duration_ms, Some(1_500));
}

#[test]
fn a_markless_pane_stamps_its_synthetic_block_from_the_first_feed_and_the_boundary() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"banner\r\n", 10_000);
    core.feed_at(b"more\r\n", 12_000);
    let running = records(&core);
    assert_eq!(running.len(), 1);
    assert_eq!(running[0].state, BlockState::Running);
    assert_eq!(running[0].started_at_ms, Some(10_000));
    assert_eq!(running[0].finished_at_ms, None);
    core.feed_at(b"\x1b]7000;v=1;boundary=0\x07next\r\n", 20_000);
    let after = records(&core);
    let closed = after.iter().find(|b| b.state == BlockState::Finished).expect("closed synthetic");
    assert_eq!(closed.started_at_ms, Some(10_000));
    assert_eq!(closed.finished_at_ms, Some(20_000));
    let trailing = after.iter().find(|b| b.state == BlockState::Running).expect("new trailing block");
    assert_eq!(trailing.started_at_ms, Some(20_000));
}

#[test]
fn a_block_closed_by_the_next_prompt_is_finished_at_that_prompts_clock() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 4);
    core.feed_at(b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07one\r\n", 1_000);
    core.feed_at(b"\x1b]133;A\x07", 3_000);
    let blocks = records(&core);
    let abandoned = blocks.iter().find(|b| b.state == BlockState::Abandoned).expect("abandoned");
    assert_eq!(abandoned.started_at_ms, Some(1_000));
    assert_eq!(abandoned.finished_at_ms, Some(3_000));
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && cargo test -p vt-core --test block_timestamps` → compile error: no field `started_at_ms` on `BlockRecord`.

- [ ] **Step 3: Implement the fallback and the record fields**

`block.rs`: `BlockRecord` gains `pub started_at_ms: Option<u64>` and `pub finished_at_ms: Option<u64>` after `duration_ms`.

`block_grid.rs`: fields `clock_ms: u64` and `trailing_started_at_ms: Option<u64>` (both zero/`None` in `new`), and

```rust
    pub fn set_clock(&mut self, now_ms: u64) {
        self.clock_ms = now_ms;
    }

    pub fn note_output(&mut self) {
        if self.open.is_none() && self.trailing_started_at_ms.is_none() {
            self.trailing_started_at_ms = Some(self.clock_ms);
        }
    }

    pub fn trailing_started_at_ms(&self) -> Option<u64> {
        self.trailing_started_at_ms
    }
```

In `open_block`: the abandoned previous block gets `prev.meta.finished_at_ms.get_or_insert(self.clock_ms);` before it is pushed; the new block's meta, after `std::mem::take(&mut self.pending_meta)`, gets `started_at_ms` filled: build it as `let mut meta = std::mem::take(&mut self.pending_meta); meta.started_at_ms.get_or_insert(self.clock_ms);` and `self.trailing_started_at_ms = None;`. In `close_block`: `block.meta.finished_at_ms.get_or_insert(self.clock_ms);`. In `push_synthetic`: the meta becomes

```rust
            meta: BlockMeta {
                exit_code,
                started_at_ms: self.trailing_started_at_ms.take(),
                finished_at_ms: Some(self.clock_ms),
                ..BlockMeta::default()
            },
```

`parser.rs`: `pub(crate) fn set_clock(&mut self, now_ms: u64) { self.grid.set_clock(now_ms); }` and `pub(crate) fn note_output(&mut self) { self.grid.note_output(); }`. `lib.rs` `feed_raw`: first line `self.parser.set_clock(self.now_ms);`; after the trailing `advance_vte` (before `self.parser.commit_evicted()`): `self.parser.note_output();`. (`tick` reaches `feed_raw` through `flush_sync`, so a deadline flush uses the tick's clock.)

`grid.rs` `export_blocks`: the loop's record gets `started_at_ms: started, finished_at_ms: finished,` (the two locals already exist); the `grid.is_empty()` record and the trailing record get `started_at_ms: grid.trailing_started_at_ms(), finished_at_ms: None,`.

Run: `cargo test -p vt-core` → PASS (`BlockRecord` literals in `exit_encoding.rs` fail to compile until Step 4 — vt-core's own tests do not construct one).

- [ ] **Step 4: The 18-word record**

`crates/vt-wasm/tests/exit_encoding.rs`: `record()` gains `started_at_ms: None, finished_at_ms: None,`; add:

```rust
fn record_at(started: Option<u64>, finished: Option<u64>) -> BlockRecord {
    BlockRecord { started_at_ms: started, finished_at_ms: finished, ..record(None) }
}

fn encode_record(record: BlockRecord) -> Vec<u32> {
    let snapshot = vt_core::GridSnapshot { blocks: vec![record], ..empty_snapshot() };
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&snapshot).unwrap();
    buffers.blocks().to_vec()
}

#[test]
fn timestamps_take_words_fourteen_to_seventeen_with_max_pairs_for_none() {
    let words = encode_record(record_at(Some(0x1_0000_0002), None));
    assert_eq!(words.len(), vt_wasm::BLOCK_RECORD_WORDS);
    assert_eq!(&words[14..18], &[2, 1, u32::MAX, u32::MAX]);
    let none = encode_record(record_at(None, Some(7)));
    assert_eq!(&none[14..18], &[u32::MAX, u32::MAX, 7, 0]);
}
```

(refactor `encode` so the `GridSnapshot` literal lives in an `empty_snapshot()` helper returning a snapshot with `blocks: Vec::new()`; `encode(exit)` becomes `encode_record(record(exit))`.) `export.rs`: `pub const BLOCK_RECORD_WORDS: usize = 18;`; in `write_blocks`, after the `git_branch` pair, push the two timestamps with the `duration_ms` encoding:

```rust
            for stamp in [record.started_at_ms, record.finished_at_ms] {
                let (lo, hi) = match stamp {
                    None => (u32::MAX, u32::MAX),
                    Some(ms) => (ms as u32, (ms >> 32) as u32),
                };
                self.blocks.push(lo);
                self.blocks.push(hi);
            }
```

Run: `cargo test -p vt-wasm` → PASS.

- [ ] **Step 5: TS — `BlockView`, the clock, `onBlockFinished`**

`ts/core/src/blocks.ts`: `BLOCK_RECORD_WORDS = 18`; in `decodeBlockRecords` add a local `const stampAt = (index: number): number | null => { const lo = blocks[base + index]; const hi = blocks[base + index + 1]; return lo === 0xffffffff && hi === 0xffffffff ? null : hi * 2 ** 32 + lo; };` and push `startedAtMs: stampAt(14), finishedAtMs: stampAt(16),`. `types.ts` `BlockView`: `startedAtMs: number | null; finishedAtMs: number | null;` after `durationMs`. `block-contract.test.ts:51-56`: after `words[7] = 0xffffffff;` add `words[14] = 0xffffffff; words[15] = 0xffffffff; words[16] = 0xffffffff; words[17] = 0xffffffff;` (the test's decoded expectation, if it spells the whole object, gains `startedAtMs: null, finishedAtMs: null`).

`terminal-core.ts`: `feed` calls `this.inner.feed(bytes, Date.now())`; rename the existing `nowMs()` helper to `budgetNow()` (still `performance.now()`), used only by `drain`. `terminal-core.test.ts:306` "tick past the deadline": `const start = Date.now();`. `dom-block-renderer.ts:472`: `this.core?.tick(Date.now());`. Add to `terminal-core.test.ts`:

```ts
	it("stamps a block from the wall clock so it compares with the shell hook's epoch stamps", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const before = Date.now();
		core.feed(new TextEncoder().encode("\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07x\r\n\x1b]133;D;0\x07"));
		const block = decodeBlocks(core.snapshot()).find((candidate) => candidate.state === "finished")!;
		expect(block.startedAtMs).toBeGreaterThanOrEqual(before);
		expect(block.finishedAtMs).toBeGreaterThanOrEqual(block.startedAtMs!);
		expect(block.finishedAtMs).toBeLessThanOrEqual(Date.now());
	});
```

`ts/renderer-dom/src/block-finished.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import type { BlockView } from "@operator/terminal-core";
import { finishedBlocks, rendererVisible } from "./block-finished";

function block(id: string, state: BlockView["state"]): BlockView {
	return { id, firstRow: 0, rowCount: 1, state, source: "osc133", exitCode: state === "finished" ? 0 : null, durationMs: state === "finished" ? 10 : null, startedAtMs: 1, finishedAtMs: state === "finished" ? 11 : null, command: "", cwd: "", gitBranch: "", bookmarked: false };
}

describe("finishedBlocks", () => {
	it("reports a block that was running last paint and is finished or abandoned now", () => {
		const previous = new Map([["a", "running" as const], ["b", "running" as const]]);
		const now = [block("a", "finished"), block("b", "abandoned"), block("c", "finished")];
		expect(finishedBlocks(previous, now).map((b) => b.id)).toEqual(["a", "b"]);
	});
	it("does not report a block first seen already finished, nor one still running", () => {
		expect(finishedBlocks(new Map(), [block("a", "finished")])).toEqual([]);
		expect(finishedBlocks(new Map([["a", "running" as const]]), [block("a", "running")])).toEqual([]);
	});
});

describe("rendererVisible", () => {
	it("is false for a detached or inert container and true for one in layout", () => {
		const detached = document.createElement("div");
		expect(rendererVisible(detached)).toBe(false);
		const parked = document.createElement("div");
		parked.setAttribute("inert", "");
		const inner = document.createElement("div");
		parked.append(inner);
		document.body.append(parked);
		expect(rendererVisible(inner)).toBe(false);
		const shown = document.createElement("div");
		document.body.append(shown);
		shown.getClientRects = () => [{}] as unknown as DOMRectList;
		expect(rendererVisible(shown)).toBe(true);
	});
});
```

Add to `dom-block-renderer.test.ts` (inside `describe("DomBlockRenderer")`):

```ts
	it("fires onBlockFinished once when a running block finishes, with the pane's visibility", async () => {
		const { core, host, renderer } = mountWith("\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07out\r\n");
		host.getClientRects = () => [{}] as unknown as DOMRectList;
		const events: unknown[] = [];
		renderer.onBlockFinished((event) => events.push(event));
		await flushRepaint();
		feed(core, "\x1b]133;D;3\x07");
		await flushRepaint();
		await flushRepaint();
		expect(events).toHaveLength(1);
		expect(events[0]).toMatchObject({ exitCode: 3, visible: true });
		expect((events[0] as { durationMs: number | null }).durationMs).not.toBeNull();
	});
```

Add to `TerminalSurface.test.tsx` (inside the existing top-level `describe`, beside the `features` test, using the same helpers):

```ts
	it("forwards onBlockFinished from the renderer", () => {
		const onBlockFinished = vi.fn();
		const listen = vi.spyOn(DomBlockRenderer.prototype, "onBlockFinished");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} onBlockFinished={onBlockFinished} />,
		);
		expect(listen).toHaveBeenCalledTimes(1);
		const listener = listen.mock.calls[0]![0] as (event: unknown) => void;
		listener({ id: "0:1", exitCode: 0, durationMs: 5, visible: true });
		expect(onBlockFinished).toHaveBeenCalledWith({ id: "0:1", exitCode: 0, durationMs: 5, visible: true });
		listen.mockRestore();
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/block-finished.test.ts` → FAIL, module not found.

- [ ] **Step 6: Implement `block-finished.ts`, the renderer hook, the prop**

`ts/renderer-dom/src/block-finished.ts`:

```ts
import type { BlockId, BlockState, BlockView } from "@operator/terminal-core";

export type BlockFinishedEvent = Readonly<{ id: BlockId; exitCode: number | null; durationMs: number | null; visible: boolean }>;

export function finishedBlocks(previous: ReadonlyMap<BlockId, BlockState>, blocks: readonly BlockView[]): BlockView[] {
	return blocks.filter((block) => previous.get(block.id) === "running" && block.state !== "running");
}

export function rendererVisible(container: HTMLElement): boolean {
	if (!container.isConnected || container.closest("[inert]") !== null) return false;
	if (typeof document !== "undefined" && document.visibilityState === "hidden") return false;
	return container.getClientRects().length > 0;
}
```

`dom-block-renderer.ts`: fields `private blockStates = new Map<BlockId, BlockState>();` and `private readonly blockFinishedListeners = new Set<(event: BlockFinishedEvent) => void>();`; method

```ts
	onBlockFinished(listener: (event: BlockFinishedEvent) => void): () => void {
		this.blockFinishedListeners.add(listener);
		return () => {
			this.blockFinishedListeners.delete(listener);
		};
	}
```

In `repaint`, right after `const blocks = decodeBlocks(snapshot);`:

```ts
		const finished = finishedBlocks(this.blockStates, blocks);
		this.blockStates = new Map(blocks.map((block) => [block.id, block.state] as const));
		if (finished.length > 0) {
			const visible = rendererVisible(container);
			for (const block of finished) {
				for (const listener of [...this.blockFinishedListeners]) {
					listener({ id: block.id, exitCode: block.exitCode, durationMs: block.durationMs, visible });
				}
			}
		}
```

`dispose()` clears both. `index.ts`: `export { type BlockFinishedEvent } from "./block-finished.js";`. `TerminalSurface.tsx`: prop `onBlockFinished?: (event: BlockFinishedEvent) => void;` (import the type from `@operator/terminal-renderer-dom`), a ref `const onBlockFinishedRef = useRef(onBlockFinished); onBlockFinishedRef.current = onBlockFinished;`, and in the mount effect after `const offPaint = …`: `const offFinished = renderer.onBlockFinished((event) => onBlockFinishedRef.current?.(event));` with `offFinished();` in the cleanup.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 7: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test` → clean, PASS.
- `cargo build --release -p vt-host --target wasm32-unknown-unknown && cp target/wasm32-unknown-unknown/release/vt_host.wasm ../../backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && (cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/...)` → PASS.
- `npm run bench:feel` → `PASS feel gate: zero pixel diff` (both fixtures' blocks are synthetic, whose header is the plain one — no duration is drawn). `npm run bench:agent:gate` → PASS (the tick clock changed; the torn-paint row is the guard).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean. `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

CHANGELOG:

```markdown
- vt-core/vt-wasm/core: a block missing the hook's `start_ms`/`end_ms` is stamped from the clock `feed_at` was last called with — open and close for OSC 133 blocks, first feed and process boundary for the synthetic blocks of a markless pane (Kitty `window.py` `handle_cmd_end`, VS Code `ITerminalCommand.timestamp`). `BlockRecord`/`BlockView` carry `startedAtMs`/`finishedAtMs` (`BLOCK_RECORD_WORDS = 18`). A shell without the bootstrap hook therefore shows a duration in its block header where it showed none. The TS core now feeds and ticks with `Date.now()` so its stamps are epoch milliseconds like the Go mirror's and the hook's.
- renderer-dom/react: `DomBlockRenderer.onBlockFinished` / the `onBlockFinished` prop of `TerminalSurface` fire `{ id, exitCode, durationMs, visible }` when a block that was running on the previous paint is finished or abandoned; `visible` says whether the pane was in layout, not `inert`, and the document visible. The host decides what to do with it.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/crates packages/terminal/ts packages/terminal/CHANGELOG.md backend/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm && git commit -m "vt-core: block timestamps fall back to the feed clock; onBlockFinished from the renderer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 5: The link grammar — a port of VS Code's `terminalLinkParsing.ts` with its test table

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/link-parsing.ts`
- Create: `packages/terminal/ts/renderer-dom/src/link-parsing.test.ts`
- Create: `packages/terminal/ts/renderer-dom/src/VSCODE-LINK-PARSING-ATTRIBUTION.md` and `packages/terminal/ts/renderer-dom/src/LICENSE-VSCODE-MIT`

**Interfaces:**
- Consumes: nothing in the tree. Source: `/Users/omaraly/development/AI/vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts` (430 lines) and `/Users/omaraly/development/AI/vscode/src/vs/workbench/contrib/terminalContrib/links/test/browser/terminalLinkParsing.test.ts` (871 lines), VS Code commit `d3c24c3` (`git -C /Users/omaraly/development/AI/vscode rev-parse --short HEAD` — write the hash you read, not this one, if it differs).
- Produces: the "Link grammar" shapes above. Task 6's `createPathProvider` calls `detectLinks(line.text, os)`; Task 7's `file-line` rule is independent (Kitty's regex).

The port is mechanical and the test table travels verbatim — the brief forbids inventing cases. The only changes are the ones listed; if a step needs a change not listed here, stop and say so rather than "adapting".

- [ ] **Step 1: Copy the attribution and the licence**

`packages/terminal/ts/renderer-dom/src/LICENSE-VSCODE-MIT`: the contents of `/Users/omaraly/development/AI/vscode/LICENSE.txt`, unchanged.

`packages/terminal/ts/renderer-dom/src/VSCODE-LINK-PARSING-ATTRIBUTION.md`:

```markdown
# Link parsing

`link-parsing.ts` and `link-parsing.test.ts` are ports of
`src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts` and
`src/vs/workbench/contrib/terminalContrib/links/test/browser/terminalLinkParsing.test.ts`
from Visual Studio Code (https://github.com/microsoft/vscode, commit `<hash>`),
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
```

- [ ] **Step 2: Write the test file (the port of the table)**

Copy `/Users/omaraly/development/AI/vscode/src/vs/workbench/contrib/terminalContrib/links/test/browser/terminalLinkParsing.test.ts` to `packages/terminal/ts/renderer-dom/src/link-parsing.test.ts` and apply exactly:

1. Replace the header imports with
   ```ts
   import { describe, expect, it } from "vitest";
   import { detectLinks, detectLinkSuffixes, getLinkSuffix, type LinkOs, type ParsedLink, removeLinkQueryString, removeLinkSuffix } from "./link-parsing";
   ```
2. Replace the `operatingSystems` / `osTestPath` / `osLabel` declarations with
   ```ts
   const operatingSystems: ReadonlyArray<LinkOs> = ["posix", "windows"];
   const osTestPath: Record<LinkOs, string> = { posix: "/test/path/linux", windows: "C:\\test\\path\\windows" };
   const osLabel: Record<LinkOs, string> = { posix: "[posix]", windows: "[Windows]" };
   ```
   (the table's macOS row used the same grammar as Linux; `"posix"` runs it once).
3. `OperatingSystem.Linux` and `OperatingSystem.Macintosh` → `"posix"`; `OperatingSystem.Windows` → `"windows"`.
4. `suite(` → `describe(`; `test(` → `it(`; `deepStrictEqual(A, B)` → `expect(A).toStrictEqual(B)`; `deepStrictEqual(A, B, message)` → `expect(A, message).toStrictEqual(B)`; `strictEqual(A, B)` → `expect(A).toBe(B)`; `ok(A, message)` → `expect(A, message).toBeTruthy()`; delete the `ensureNoDisposablesAreLeakedInTestSuite();` line; `IParsedLink` → `ParsedLink`.
5. Nothing else. `wc -l` of the result is within a few lines of 871.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/link-parsing.test.ts` → FAIL, module `./link-parsing` not found.

- [ ] **Step 3: Write the implementation (the port of the module)**

Copy `/Users/omaraly/development/AI/vscode/src/vs/workbench/contrib/terminalContrib/links/browser/terminalLinkParsing.ts` to `packages/terminal/ts/renderer-dom/src/link-parsing.ts` and apply exactly:

1. Delete the two `import` lines. Add at the top (below the Microsoft header comment, which stays — it is the attribution the licence requires):
   ```ts
   export type LinkOs = "posix" | "windows";

   export const LINK_MAX_LINE_LENGTH = 2000;
   export const LINK_MAX_RESOLVED_PER_LINE = 10;
   export const LINK_MAX_RESOLVED_LENGTH = 1024;

   function lazy<T>(make: () => T): { readonly value: T } {
   	let made: { value: T } | null = null;
   	return {
   		get value(): T {
   			if (!made) made = { value: make() };
   			return made.value;
   		},
   	};
   }
   ```
2. `new Lazy<RegExp>(() => …)` → `lazy<RegExp>(() => …)` (three sites: `linkSuffixRegexEol`, `linkSuffixRegex`, `gitDiffLineRegex`, `gitDiffTextRegex` — four).
3. `IParsedLink` → `ParsedLink`, `ILinkSuffix` → `LinkSuffix`, `ILinkPartialRange` → `LinkPartialRange` (declarations and every use).
4. `detectLinks(line: string, os: OperatingSystem)` → `detectLinks(line: string, os: LinkOs): ParsedLink[]`; `detectPathsNoSuffix(line: string, os: OperatingSystem)` → `(line: string, os: LinkOs)`; `os === OperatingSystem.Windows` → `os === "windows"`.
5. Nothing else; `enum RegexPathConstants` stays an enum.

Run: `npx vitest run src/link-parsing.test.ts` → PASS, every table row. If a row fails, the substitution list above was applied unevenly — diff against the source before touching the grammar.

- [ ] **Step 4: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`: `npm run build:ts && (cd ts/renderer-dom && npx vitest run)` → PASS; `npm run bench:feel` → `PASS feel gate: zero pixel diff` (nothing reads the module yet).

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts/renderer-dom/src/link-parsing.ts packages/terminal/ts/renderer-dom/src/link-parsing.test.ts packages/terminal/ts/renderer-dom/src/VSCODE-LINK-PARSING-ATTRIBUTION.md packages/terminal/ts/renderer-dom/src/LICENSE-VSCODE-MIT && git commit -m "renderer-dom: port VS Code's terminal link grammar with its test table

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The linkifier — hover, per-logical-line providers, the underline overlay, modifier click, the pointing hand; the act-probe fixture and the affordance gate

**Files:**
- Create: `packages/terminal/bench/agent-session/make-act-probe.mjs`, `packages/terminal/bench/agent-session/probes/act-probe/{recording,size.json}`, `packages/terminal/bench/agent-session/affordance-gate.mjs`, `packages/terminal/bench/agent-session/baselines/act-probe/` (recorded by the feel gate and the affordance gate)
- Modify: `packages/terminal/bench/agent-session/{main.ts,session-api.test.mjs,fixtures.test.mjs}`, `packages/terminal/package.json` (`bench:affordances`)
- Modify: `packages/terminal/ts/renderer-dom/src/clusters.ts`, `clusters.test.ts`
- Create: `packages/terminal/ts/renderer-dom/src/{logical-lines.ts,logical-lines.test.ts,link-providers.ts,link-providers.test.ts,linkifier.ts,linkifier.test.ts,decorations.ts,decorations.test.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{selection-text.ts,selection-view.ts,dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,styles-parity.test.ts,index.ts}`
- Modify: `packages/terminal/ts/core/src/types.ts` (`resolvePath?`, `openPath?` on `HostCapabilities`)
- Modify: `packages/terminal/ts/react/src/{selection-gesture.ts,selection-gesture.test.ts,surface-geometry.ts,TerminalSurface.tsx,TerminalSurface.mouse.test.tsx}`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `TextRows` + `rowWrapped` (Task 1), `STYLE_WORD_LINK`, `TerminalCore.linkUri` (Task 2), `detectLinks`, `LinkOs`, the three caps (Task 5), `rowClusters`/`cellCount` (`clusters.ts`), `pointAt`/`renderedRows`/`paintSelectionFill` (`dom-block-renderer.ts`), `SelectionPoint`, `onMouseDown` (`TerminalSurface.tsx:386`), `HostCapabilities.openLink`, the feel gate's page (`bench/agent-session/main.ts`).
- Produces: the "Linkifier" shapes above, `HostCapabilities.resolvePath?` and `openPath?` in `ts/core/src/types.ts` (implemented by Operator in Task 9), the act-probe fixture, `npm run bench:affordances -- --action hover`. Task 7 reuses `logicalLineAt`, `LinkRange`, `decorations.ts` and the probe; Task 8 reuses `logicalLineAt` and the probe.

The shape is xterm.js's (`src/browser/Linkifier.ts`): on pointer move ask the providers for the *hovered logical line only*, cache per line until the buffer changes, underline the link under the pointer, activate on a press with the platform modifier; providers are async so a host can validate paths against its file system (`resolvePath`). Providers run in priority order — OSC 8 first, then the URL grammar, then the path grammar — and a later provider's link that overlaps an earlier one is dropped (`_removeIntersectingLinks`). The underline is an overlay in a decoration layer appended to the scroll container, positioned from row geometry the way the selection fill is (`selection-view.ts` `renderedRows`), so the row pool never sees it. The pointer becomes a hand only while a link is under it (Warp `app/src/terminal/view.rs:18796` `set_cursor_shape(Cursor::PointingHand)` / `reset_cursor`).

- [ ] **Step 1: The act-probe fixture and its baseline**

`packages/terminal/bench/agent-session/make-act-probe.mjs`:

```js
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "probes", "act-probe");
const ESC = "\x1b";
const osc8 = (uri) => `${ESC}]8;;${uri}${ESC}\\`;
const lines = [
	"Open https://example.com/docs and src/app/main.ts:42 or lib/util.go:7:3 now",
	`See ${osc8("https://example.org/x")}the linked text${osc8("")} and plain text after`,
	`wrap: https://example.com/${"a".repeat(90)}/end tail`,
	`token ghp_${"A".repeat(36)} key AKIA${"B".repeat(16)} end`,
	"--- a/foo/bar.ts",
	"+++ b/foo/bar.ts",
	"sha 0123456789abcdef uuid 123e4567-e89b-12d3-a456-426614174000 #ff8800 10.0.0.1 0xdeadbeef 123456",
	`[docs](https://example.com/md) sha256:${"c".repeat(64)}`,
];
await mkdir(dir, { recursive: true });
await writeFile(path.join(dir, "recording"), Buffer.from(`${lines.join("\r\n")}\r\n`, "utf8"));
await writeFile(path.join(dir, "size.json"), `${JSON.stringify([{ offset: 0, cols: 80, rows: 24 }])}\n`);
process.stdout.write(`wrote ${dir}\n`);
```

Run `node /Users/omaraly/development/AI/Operator/packages/terminal/bench/agent-session/make-act-probe.mjs`. In `fixtures.test.mjs`, the probe test's `assert.ok(probes.includes("glyph-probe"), …)` gains a sibling `assert.ok(probes.includes("act-probe"), …)`; run `node --test ./bench/agent-session/fixtures.test.mjs` → PASS. Run `npm run bench:feel` → five `recorded act-probe/offset-N.png` lines (a missing baseline is recorded, `feel-gate.mjs:52-56`) and `PASS feel gate: zero pixel diff` for the existing fixtures. Open `baselines/act-probe/offset-0.png` and confirm the eight lines are there, line 3 wrapped onto a second row, nothing underlined.

- [ ] **Step 2: Failing tests — coordinates, logical lines, providers, linkifier, decorations**

`clusters.test.ts` — add (import `cellAtByte, cellAtOffset, offsetAtByte, rowCoordinates` from `./clusters`):

```ts
describe("rowCoordinates", () => {
	it("maps cell, byte and utf-16 offset for ascii, wide and astral clusters", () => {
		expect(rowCoordinates("a漢b", [1, 4, 2])).toEqual([
			{ cell: 0, byte: 0, offset: 0 },
			{ cell: 1, byte: 1, offset: 1 },
			{ cell: 3, byte: 4, offset: 2 },
			{ cell: 4, byte: 5, offset: 3 },
		]);
		expect(cellAtOffset("a漢b", [1, 4, 2], 2)).toBe(3);
		expect(cellAtOffset("a漢b", [1, 4, 2], 3)).toBe(4);
		expect(cellAtByte("a漢b", [1, 4, 2], 4)).toBe(3);
		expect(offsetAtByte("a漢b", [1, 4, 2], 5)).toBe(3);
		expect(cellAtOffset("x🚀y", [1, 5, 2], 3)).toBe(3);
	});
});
```

`logical-lines.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { logicalLineAt, rangeContains } from "./logical-lines";
import type { TextRows } from "./selection-text";

const rows: TextRows = {
	blockIds: ["b"],
	firstRow: () => 10,
	rowCount: () => 4,
	rowText: (_id, row) => ["one ", "two", "three", "four"][row - 10] ?? "",
	rowSpans: () => [],
	rowWrapped: (_id, row) => row === 10,
	rowLinkRuns: (_id, row) => (row === 10 ? [0, 3, 7] : row === 11 ? [0, 3, 7] : []),
	linkUri: (id) => (id === 7 ? "https://seven" : null),
};

describe("logicalLineAt", () => {
	it("joins the wrapped pair and leaves the others alone", () => {
		const line = logicalLineAt(rows, "b", 11)!;
		expect(line).toMatchObject({ blockId: "b", firstRow: 10, rowCount: 2, text: "one two", rowOffsets: [0, 4] });
		expect(logicalLineAt(rows, "b", 12)).toMatchObject({ firstRow: 12, rowCount: 1, text: "three" });
		expect(logicalLineAt(rows, "b", 9)).toBeNull();
		expect(logicalLineAt(rows, "x", 10)).toBeNull();
	});
	it("maps string offsets to cells across the wrap and lifts link runs into line offsets", () => {
		const line = logicalLineAt(rows, "b", 10)!;
		expect(line.rangeOf(2, 6)).toEqual({ blockId: "b", startRow: 10, startCell: 2, endRow: 11, endCell: 2 });
		expect(line.rangeOf(0, 4)).toEqual({ blockId: "b", startRow: 10, startCell: 0, endRow: 10, endCell: 4 });
		expect(line.linkRuns).toEqual([
			{ startOffset: 0, endOffset: 3, linkId: 7 },
			{ startOffset: 4, endOffset: 7, linkId: 7 },
		]);
		expect(line.linkUri(7)).toBe("https://seven");
	});
});

describe("rangeContains", () => {
	const range = { blockId: "b", startRow: 10, startCell: 2, endRow: 11, endCell: 2 };
	it("is inclusive of the start cell, exclusive of the end cell, and whole rows in between", () => {
		expect(rangeContains(range, 10, 1)).toBe(false);
		expect(rangeContains(range, 10, 2)).toBe(true);
		expect(rangeContains(range, 10, 70)).toBe(true);
		expect(rangeContains(range, 11, 1)).toBe(true);
		expect(rangeContains(range, 11, 2)).toBe(false);
		expect(rangeContains(range, 12, 0)).toBe(false);
	});
});
```

`link-providers.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { createPathProvider, hyperlinkProvider, urlProvider } from "./link-providers";
import { logicalLineAt } from "./logical-lines";
import type { TextRows } from "./selection-text";

function lineOf(text: string, links: number[] = [], uri: string | null = null) {
	const rows: TextRows = {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => 1,
		rowText: () => text,
		rowSpans: () => [],
		rowWrapped: () => false,
		rowLinkRuns: () => links,
		linkUri: () => uri,
	};
	return logicalLineAt(rows, "b", 0)!;
}

describe("hyperlinkProvider", () => {
	it("turns contiguous runs of one link id into one link with its uri", async () => {
		const line = lineOf("see here now", [4, 6, 3, 6, 8, 3], "https://h");
		expect(await hyperlinkProvider(line)).toEqual([
			{ kind: "hyperlink", text: "here", uri: "https://h", range: { blockId: "b", startRow: 0, startCell: 4, endRow: 0, endCell: 8 } },
		]);
	});
	it("drops a run whose id the registry cannot resolve", async () => {
		expect(await hyperlinkProvider(lineOf("x", [0, 1, 9], null))).toEqual([]);
	});
});

describe("urlProvider", () => {
	it("matches xterm.js's strict url grammar and stops before trailing punctuation", async () => {
		const links = await urlProvider(lineOf("go to https://x.y/a?b=c, then (https://z.w/p) done"));
		expect(links.map((link) => link.uri)).toEqual(["https://x.y/a?b=c", "https://z.w/p"]);
		expect(links[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 6, endRow: 0, endCell: 23 });
	});
	it("finds nothing in plain text", async () => {
		expect(await urlProvider(lineOf("no links here"))).toEqual([]);
	});
});

describe("createPathProvider", () => {
	it("asks the host for each candidate and keeps only the ones that resolve, with row and column", async () => {
		const asked: string[] = [];
		const provider = createPathProvider(async (path, cwd) => {
			asked.push(`${cwd}:${path}`);
			return path.endsWith(".ts") ? `/abs/${path}` : null;
		}, () => "/work", "posix");
		const links = await provider(lineOf("edit src/a.ts:42:7 or lib/b.go:9"));
		expect(asked).toEqual(["/work:src/a.ts", "/work:lib/b.go"]);
		expect(links).toEqual([
			{ kind: "path", text: "src/a.ts:42:7", path: "/abs/src/a.ts", line: 42, column: 7, range: { blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 18 } },
		]);
	});
	it("does not hand a url to the host and caches an answer per path and cwd", async () => {
		let calls = 0;
		const provider = createPathProvider(async () => { calls += 1; return "/x"; }, () => "", "posix");
		expect(await provider(lineOf("https://x.y/a"))).toEqual([]);
		await provider(lineOf("./same"));
		await provider(lineOf("./same"));
		expect(calls).toBe(1);
	});
});
```

`linkifier.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { Linkifier } from "./linkifier";
import type { DetectedLink, LinkProvider } from "./link-providers";
import type { TextRows } from "./selection-text";

function rowsWith(text: string): TextRows {
	return { blockIds: ["b"], firstRow: () => 0, rowCount: () => 1, rowText: () => text, rowSpans: () => [], rowWrapped: () => false };
}

async function settle(): Promise<void> {
	await new Promise((resolve) => setTimeout(resolve, 0));
}

describe("Linkifier", () => {
	it("asks the providers for the hovered line once per generation and reports the link under the pointer", async () => {
		const provider = vi.fn<LinkProvider>(async (line) => [
			{ kind: "url", text: "https://x.y", uri: "https://x.y", range: line.rangeOf(4, 15) },
		]);
		let generation = 1;
		const onChange = vi.fn();
		const linkifier = new Linkifier({ rows: () => rowsWith("see https://x.y now"), generation: () => generation, providers: () => [provider], onChange });
		linkifier.hover({ blockId: "b", row: 0, column: 6, side: "left" });
		await settle();
		expect(linkifier.current()?.uri).toBe("https://x.y");
		expect(onChange).toHaveBeenCalledTimes(1);
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
		expect(provider).toHaveBeenCalledTimes(1);
		generation = 2;
		linkifier.refresh();
		await settle();
		expect(provider).toHaveBeenCalledTimes(2);
	});
	it("prefers an earlier provider's link when a later one overlaps it", async () => {
		const first: LinkProvider = async (line) => [{ kind: "hyperlink", text: "a", uri: "https://first", range: line.rangeOf(0, 5) }];
		const second: LinkProvider = async (line) => [{ kind: "url", text: "b", uri: "https://second", range: line.rangeOf(3, 9) }];
		const linkifier = new Linkifier({ rows: () => rowsWith("abcdefghij"), generation: () => 1, providers: () => [first, second], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 4, side: "left" });
		await settle();
		expect(linkifier.current()?.uri).toBe("https://first");
		linkifier.hover({ blockId: "b", row: 0, column: 7, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
	});
	it("ignores a resolution that lands after the pointer moved on", async () => {
		let release: (links: DetectedLink[]) => void = () => undefined;
		const slow: LinkProvider = () => new Promise((resolve) => { release = resolve; });
		const linkifier = new Linkifier({ rows: () => rowsWith("abc"), generation: () => 1, providers: () => [slow], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		linkifier.hover(null);
		release([{ kind: "url", text: "abc", uri: "https://late", range: { blockId: "b", startRow: 0, startCell: 0, endRow: 0, endCell: 3 } }]);
		await settle();
		expect(linkifier.current()).toBeNull();
	});
});
```

`decorations.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { paintBoxes, rangeBoxes } from "./decorations";
import type { RenderedRow } from "./selection-view";

function row(rowNumber: number, top: number): RenderedRow {
	const element = document.createElement("div");
	return { element, box: { blockId: "b", row: rowNumber, firstRow: 0, rowCount: 3, left: 100, top, bottom: top + 20, width: 400 } };
}

describe("rangeBoxes", () => {
	it("cuts the first and last rows by cell and covers whole rows between, in container coordinates", () => {
		const container = document.createElement("div");
		container.getBoundingClientRect = () => ({ left: 90, top: 40, right: 690, bottom: 640, width: 600, height: 600, x: 90, y: 40, toJSON: () => ({}) }) as DOMRect;
		Object.defineProperty(container, "scrollTop", { value: 300, configurable: true });
		Object.defineProperty(container, "scrollLeft", { value: 0, configurable: true });
		const rows = [row(0, 50), row(1, 70), row(2, 90)];
		const boxes = rangeBoxes({ blockId: "b", startRow: 0, startCell: 2, endRow: 2, endCell: 3 }, rows, 10, container);
		expect(boxes).toEqual([
			{ left: 30, top: 310, width: 380, height: 20 },
			{ left: 10, top: 330, width: 400, height: 20 },
			{ left: 10, top: 350, width: 30, height: 20 },
		]);
	});
	it("returns nothing for a row that is not rendered", () => {
		const container = document.createElement("div");
		expect(rangeBoxes({ blockId: "b", startRow: 7, startCell: 0, endRow: 7, endCell: 1 }, [row(0, 0)], 10, container)).toEqual([]);
	});
});

describe("paintBoxes", () => {
	it("reuses elements, sets geometry and labels, and removes the surplus", () => {
		const layer = document.createElement("div");
		paintBoxes(layer, "terminal-link-underline", [{ left: 1, top: 2, width: 3, height: 4 }, { left: 5, top: 6, width: 7, height: 8 }]);
		expect(layer.children).toHaveLength(2);
		const first = layer.children[0] as HTMLElement;
		expect(first.className).toBe("terminal-link-underline");
		expect(first.style.left).toBe("1px");
		expect(first.style.width).toBe("3px");
		paintBoxes(layer, "terminal-hint-label", [{ left: 0, top: 0, width: 10, height: 20 }], ["as"]);
		expect(layer.children).toHaveLength(1);
		expect(layer.children[0]).toBe(first);
		expect(first.className).toBe("terminal-hint-label");
		expect(first.textContent).toBe("as");
	});
});
```

`selection-gesture.test.ts` — add:

```ts
describe("linkModifierHeld", () => {
	const base = { metaKey: false, ctrlKey: false, altKey: false, shiftKey: false };
	it("is cmd alone on mac and ctrl alone elsewhere", () => {
		expect(linkModifierHeld({ ...base, metaKey: true }, true)).toBe(true);
		expect(linkModifierHeld({ ...base, ctrlKey: true }, true)).toBe(false);
		expect(linkModifierHeld({ ...base, ctrlKey: true }, false)).toBe(true);
		expect(linkModifierHeld({ ...base, metaKey: true }, false)).toBe(false);
		expect(linkModifierHeld({ ...base, metaKey: true, shiftKey: true }, true)).toBe(false);
	});
});
```

Add to `styles-parity.test.ts` (beside "keeps the arrow over the transcript"):

```ts
	it("shows the pointing hand only while a link is under the pointer", () => {
		const hover = terminalStyles.indexOf(".terminal-link-hover .terminal-block");
		expect(hover).toBeGreaterThan(-1);
		const block = terminalStyles.slice(hover, terminalStyles.indexOf("}", hover));
		expect(block).toContain("cursor: pointer");
	});
```

Add to `TerminalSurface.mouse.test.tsx` (inside `describe("TerminalSurface selection")`, using its `layoutRows`/`mouse` helpers and the mac-platform stub the copy-chord test uses):

```ts
	it("underlines the link under the pointer and opens it only with the platform modifier", async () => {
		const originalPlatform = Object.getOwnPropertyDescriptor(navigator, "platform");
		Object.defineProperty(navigator, "platform", { value: "MacIntel", configurable: true });
		try {
			const openLink = vi.fn(async () => {});
			const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink };
			const { container, core } = renderSurface({ host });
			act(() => { feed(core, "see https://x.y/doc now\r\n"); });
			await flushRepaint();
			const surface = container.querySelector(".terminal-host") as HTMLElement;
			const rows = layoutRows(container);
			mouse(rows[0]!, "mousemove", cellWidth * 6.5, cellHeight * 0.5);
			await new Promise((resolve) => setTimeout(resolve, 0));
			expect(surface.classList.contains("terminal-link-hover")).toBe(true);
			expect(container.querySelectorAll(".terminal-link-underline")).toHaveLength(1);
			mouse(rows[0]!, "mousedown", cellWidth * 6.5, cellHeight * 0.5, { detail: 1 });
			mouse(window, "mouseup", cellWidth * 6.5, cellHeight * 0.5);
			expect(openLink).not.toHaveBeenCalled();
			mouse(rows[0]!, "mousedown", cellWidth * 6.5, cellHeight * 0.5, { detail: 1, metaKey: true });
			mouse(window, "mouseup", cellWidth * 6.5, cellHeight * 0.5, { metaKey: true });
			expect(openLink).toHaveBeenCalledWith("https://x.y/doc");
			mouse(rows[0]!, "mousemove", cellWidth * 1.5, cellHeight * 0.5);
			await new Promise((resolve) => setTimeout(resolve, 0));
			expect(surface.classList.contains("terminal-link-hover")).toBe(false);
		} finally {
			if (originalPlatform) Object.defineProperty(navigator, "platform", originalPlatform);
		}
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/clusters.test.ts src/logical-lines.test.ts src/link-providers.test.ts src/linkifier.test.ts src/decorations.test.ts src/styles-parity.test.ts` → FAIL (missing exports / modules). `cd ../react && npx vitest run src/selection-gesture.test.ts src/TerminalSurface.mouse.test.tsx -t "link"` → FAIL.

- [ ] **Step 3: `clusters.ts` coordinates**

Add to `clusters.ts`:

```ts
export type Coordinate = Readonly<{ cell: number; byte: number; offset: number }>;

function utf8Bytes(text: string): number {
	let total = 0;
	for (const character of text) total += utf8Length(character.codePointAt(0) ?? 0);
	return total;
}

export function rowCoordinates(text: string, spans: ArrayLike<number>): Coordinate[] {
	const out: Coordinate[] = [];
	let byte = 0;
	let offset = 0;
	let cell = 0;
	for (const cluster of rowClusters(text, spans)) {
		out.push({ cell: cluster.start, byte, offset });
		byte += utf8Bytes(cluster.text);
		offset += cluster.text.length;
		cell = cluster.end;
	}
	out.push({ cell, byte, offset });
	return out;
}

function coordinateAt(coords: readonly Coordinate[], key: "byte" | "offset", value: number): Coordinate {
	for (let index = 0; index + 1 < coords.length; index += 1) {
		if (value < coords[index + 1]![key]) return coords[index]!;
	}
	return coords[coords.length - 1]!;
}

export function cellAtOffset(text: string, spans: ArrayLike<number>, offset: number): number {
	return coordinateAt(rowCoordinates(text, spans), "offset", offset).cell;
}

export function cellAtByte(text: string, spans: ArrayLike<number>, byte: number): number {
	return coordinateAt(rowCoordinates(text, spans), "byte", byte).cell;
}

export function offsetAtByte(text: string, spans: ArrayLike<number>, byte: number): number {
	return coordinateAt(rowCoordinates(text, spans), "byte", byte).offset;
}
```

- [ ] **Step 4: `logical-lines.ts`, `TextRows` link members, `snapshotTextRows`**

`selection-text.ts` `TextRows` gains `rowLinkRuns?(blockId: string, row: number): ArrayLike<number>;` and `linkUri?(id: number): string | null;`.

`packages/terminal/ts/renderer-dom/src/logical-lines.ts` — note the first import: the join itself is `ts/core`'s, and this file only lifts it into stable-row, per-block space. Do not re-derive `text` or `rowOffsets` here.

```ts
import { joinLogicalLine } from "@operator/terminal-core";
import { cellAtOffset, offsetAtByte } from "./clusters.js";
import type { TextRows } from "./selection-text.js";

export type LinkRange = Readonly<{ blockId: string; startRow: number; startCell: number; endRow: number; endCell: number }>;
export type LinkRun = Readonly<{ startOffset: number; endOffset: number; linkId: number }>;
export type LogicalLineView = Readonly<{
	blockId: string;
	firstRow: number;
	rowCount: number;
	text: string;
	rowOffsets: readonly number[];
	linkRuns: readonly LinkRun[];
	rangeOf(startOffset: number, endOffset: number): LinkRange;
	linkUri(id: number): string | null;
}>;

export function logicalLineAt(rows: TextRows, blockId: string, row: number): LogicalLineView | null {
	const first = rows.firstRow(blockId);
	const count = rows.rowCount(blockId);
	if (count <= 0 || row < first || row >= first + count) return null;
	let start = row;
	while (start > first && rows.rowWrapped(blockId, start - 1)) start -= 1;
	let end = row;
	while (end + 1 < first + count && rows.rowWrapped(blockId, end)) end += 1;
	const texts: string[] = [];
	const spans: ArrayLike<number>[] = [];
	for (let index = start; index <= end; index += 1) {
		texts.push(rows.rowText(blockId, index));
		spans.push(rows.rowSpans(blockId, index));
	}
	const { text, rowOffsets } = joinLogicalLine(texts);
	const linkRuns: LinkRun[] = [];
	for (let index = 0; index < texts.length; index += 1) {
		const runs = rows.rowLinkRuns?.(blockId, start + index) ?? [];
		for (let k = 0; k + 2 < runs.length; k += 3) {
			linkRuns.push({
				startOffset: rowOffsets[index]! + offsetAtByte(texts[index]!, spans[index]!, runs[k]!),
				endOffset: rowOffsets[index]! + offsetAtByte(texts[index]!, spans[index]!, runs[k + 1]!),
				linkId: runs[k + 2]!,
			});
		}
	}
	const rowIndexOf = (offset: number): number => {
		let index = rowOffsets.length - 1;
		while (index > 0 && rowOffsets[index]! > offset) index -= 1;
		return index;
	};
	const rangeOf = (startOffset: number, endOffset: number): LinkRange => {
		const startIndex = rowIndexOf(startOffset);
		const endIndex = endOffset > startOffset ? rowIndexOf(endOffset - 1) : startIndex;
		return {
			blockId,
			startRow: start + startIndex,
			startCell: cellAtOffset(texts[startIndex]!, spans[startIndex]!, startOffset - rowOffsets[startIndex]!),
			endRow: start + endIndex,
			endCell: cellAtOffset(texts[endIndex]!, spans[endIndex]!, endOffset - rowOffsets[endIndex]!),
		};
	};
	return {
		blockId,
		firstRow: start,
		rowCount: end - start + 1,
		text,
		rowOffsets,
		linkRuns,
		rangeOf,
		linkUri: (id) => rows.linkUri?.(id) ?? null,
	};
}

export function rangeContains(range: LinkRange, row: number, cell: number): boolean {
	if (row < range.startRow || row > range.endRow) return false;
	if (row === range.startRow && cell < range.startCell) return false;
	if (row === range.endRow && cell >= range.endCell) return false;
	return true;
}

export function rangesOverlap(a: LinkRange, b: LinkRange): boolean {
	if (a.blockId !== b.blockId) return false;
	const aStart = a.startRow * 1e9 + a.startCell;
	const aEnd = a.endRow * 1e9 + a.endCell;
	const bStart = b.startRow * 1e9 + b.startCell;
	const bEnd = b.endRow * 1e9 + b.endCell;
	return aStart < bEnd && bStart < aEnd;
}
```

`selection-view.ts` `snapshotTextRows(snapshot, filter, decoder, linkUri?: (id: number) => string | null)`: both branches gain `linkUri: (id) => linkUri?.(id) ?? null,` and a `rowLinkRuns` built from the run words by a shared helper in the file (import `STYLE_RUN_WORDS`, `STYLE_WORD_LINK` from `@operator/terminal-core`):

```ts
function linkRuns(runRanges: Uint32Array, stylePairs: Uint32Array, row: number): number[] {
	const start = runRanges[row * 2] ?? 0;
	const end = runRanges[row * 2 + 1] ?? start;
	const out: number[] = [];
	let cursor = 0;
	for (let pair = start; pair < end; pair += 1) {
		const base = pair * STYLE_RUN_WORDS;
		const runEnd = stylePairs[base] ?? cursor;
		const link = stylePairs[base + STYLE_WORD_LINK] ?? 0;
		if (link !== 0) out.push(cursor, runEnd, link);
		cursor = runEnd;
	}
	return out;
}
```

The alt branch: `rowLinkRuns: (_id, row) => linkRuns(alt.runRanges, alt.stylePairs, row),`. The primary branch guards the block bounds exactly as `rowSpans` does and calls `linkRuns(snapshot.runRanges, snapshot.stylePairs, flat)`.

- [ ] **Step 5: `link-providers.ts` and `linkifier.ts`**

`link-providers.ts`:

```ts
import { detectLinks, LINK_MAX_LINE_LENGTH, LINK_MAX_RESOLVED_LENGTH, LINK_MAX_RESOLVED_PER_LINE, type LinkOs } from "./link-parsing.js";
import type { LinkRange, LogicalLineView } from "./logical-lines.js";

export type LinkKind = "hyperlink" | "url" | "path";
export type DetectedLink = Readonly<{ kind: LinkKind; text: string; uri?: string; path?: string; line?: number; column?: number; range: LinkRange }>;
export type LinkProvider = (line: LogicalLineView) => Promise<readonly DetectedLink[]>;

// xterm.js/addons/addon-web-links/src/WebLinksAddon.ts:21 (strictUrlRegex)
const STRICT_URL = /(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\^<>`]*[^\s"':,.!?{}|\\^~\[\]`()<>]/g;
const SCHEME = /^[a-z][a-z0-9+.-]*:\/\//iu;
const PATH_CACHE_CAPACITY = 256;

export const hyperlinkProvider: LinkProvider = async (line) => {
	const out: DetectedLink[] = [];
	let index = 0;
	while (index < line.linkRuns.length) {
		const first = line.linkRuns[index]!;
		let end = first.endOffset;
		let next = index + 1;
		while (next < line.linkRuns.length && line.linkRuns[next]!.linkId === first.linkId && line.linkRuns[next]!.startOffset === end) {
			end = line.linkRuns[next]!.endOffset;
			next += 1;
		}
		const uri = line.linkUri(first.linkId);
		if (uri !== null) out.push({ kind: "hyperlink", text: line.text.slice(first.startOffset, end), uri, range: line.rangeOf(first.startOffset, end) });
		index = next;
	}
	return out;
};

export const urlProvider: LinkProvider = async (line) => {
	const out: DetectedLink[] = [];
	for (const match of line.text.matchAll(STRICT_URL)) {
		const start = match.index ?? 0;
		out.push({ kind: "url", text: match[0], uri: match[0], range: line.rangeOf(start, start + match[0].length) });
	}
	return out;
};

export function createPathProvider(
	resolve: (path: string, cwd: string) => Promise<string | null>,
	cwdOf: (blockId: string) => string,
	os: LinkOs,
): LinkProvider {
	const cache = new Map<string, Promise<string | null>>();
	const lookup = (path: string, cwd: string): Promise<string | null> => {
		const key = `${cwd} ${path}`;
		let pending = cache.get(key);
		if (!pending) {
			pending = resolve(path, cwd);
			cache.set(key, pending);
			if (cache.size > PATH_CACHE_CAPACITY) cache.delete(cache.keys().next().value as string);
		}
		return pending;
	};
	return async (line) => {
		if (line.text.length === 0 || line.text.length > LINK_MAX_LINE_LENGTH) return [];
		const cwd = cwdOf(line.blockId);
		const urls = [...line.text.matchAll(STRICT_URL)].map((match) => [match.index ?? 0, (match.index ?? 0) + match[0].length] as const);
		const out: DetectedLink[] = [];
		for (const candidate of detectLinks(line.text, os)) {
			if (out.length >= LINK_MAX_RESOLVED_PER_LINE) break;
			const raw = candidate.path.text;
			if (raw.length > LINK_MAX_RESOLVED_LENGTH || SCHEME.test(raw)) continue;
			if (urls.some(([start, end]) => candidate.path.index >= start && candidate.path.index < end)) continue;
			const resolved = await lookup(raw, cwd);
			if (resolved === null) continue;
			const start = candidate.prefix ? candidate.prefix.index : candidate.path.index;
			const end = candidate.suffix ? candidate.suffix.suffix.index + candidate.suffix.suffix.text.length : candidate.path.index + candidate.path.text.length;
			out.push({ kind: "path", text: line.text.slice(start, end), path: resolved, line: candidate.suffix?.row, column: candidate.suffix?.col, range: line.rangeOf(start, end) });
		}
		return out;
	};
}

export const DEFAULT_LINK_PROVIDERS: readonly LinkProvider[] = [hyperlinkProvider, urlProvider];
```

(`lineOf("edit src/a.ts:42:7 or lib/b.go:9")` yields exactly the two candidates the test lists because `detectLinks` finds the suffix links first and the no-suffix pass skips ranges that conflict; `cellAtOffset` on ASCII is the identity, which is why the expected cells equal string offsets. `line`/`column` are `undefined` without a suffix; `toEqual` treats an `undefined` property as absent. The `urls` guard exists because VS Code's POSIX path clause matches `//x.y/a` inside `https://x.y/a` — a URL's authority is not a file the host should be asked about.)

`linkifier.ts`:

```ts
// xterm.js/src/browser/Linkifier.ts (per-line providers, cache until the buffer changes, activate on click)
import type { DetectedLink, LinkProvider } from "./link-providers.js";
import { logicalLineAt, rangeContains, rangesOverlap } from "./logical-lines.js";
import type { SelectionPoint } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";

export type LinkifierDeps = Readonly<{
	rows(): TextRows;
	generation(): number;
	providers(): readonly LinkProvider[];
	onChange(): void;
}>;

export function mergeLinks(lists: readonly (readonly DetectedLink[])[]): DetectedLink[] {
	const accepted: DetectedLink[] = [];
	for (const list of lists) {
		for (const link of list) {
			if (accepted.some((other) => rangesOverlap(other.range, link.range))) continue;
			accepted.push(link);
		}
	}
	return accepted;
}

function sameRange(a: DetectedLink, b: DetectedLink): boolean {
	return a.range.blockId === b.range.blockId && a.range.startRow === b.range.startRow && a.range.startCell === b.range.startCell && a.range.endRow === b.range.endRow && a.range.endCell === b.range.endCell;
}

export class Linkifier {
	private readonly cache = new Map<string, Promise<readonly DetectedLink[]>>();
	private cacheGeneration = Number.NaN;
	private point: SelectionPoint | null = null;
	private link: DetectedLink | null = null;

	constructor(private readonly deps: LinkifierDeps) {}

	hover(point: SelectionPoint | null): void {
		this.point = point;
		this.refresh();
	}

	refresh(): void {
		const point = this.point;
		if (!point) {
			this.setLink(null);
			return;
		}
		const generation = this.deps.generation();
		if (generation !== this.cacheGeneration) {
			this.cache.clear();
			this.cacheGeneration = generation;
		}
		const line = logicalLineAt(this.deps.rows(), point.blockId, point.row);
		if (!line) {
			this.setLink(null);
			return;
		}
		const key = `${line.blockId}:${line.firstRow}`;
		let pending = this.cache.get(key);
		if (!pending) {
			pending = Promise.all(this.deps.providers().map((provider) => provider(line))).then(mergeLinks);
			this.cache.set(key, pending);
		}
		void pending.then(
			(links) => {
				if (this.point !== point || this.cacheGeneration !== generation) return;
				this.setLink(links.find((link) => rangeContains(link.range, point.row, point.column)) ?? null);
			},
			() => undefined,
		);
	}

	current(): DetectedLink | null {
		return this.link;
	}

	dispose(): void {
		this.cache.clear();
		this.point = null;
		this.link = null;
	}

	private setLink(link: DetectedLink | null): void {
		if (link === this.link) return;
		if (link && this.link && link.kind === this.link.kind && link.text === this.link.text && sameRange(link, this.link)) return;
		this.link = link;
		this.deps.onChange();
	}
}
```

- [ ] **Step 6: `decorations.ts`, the CSS, the renderer hooks**

`decorations.ts`:

```ts
import type { LinkRange } from "./logical-lines.js";
import type { RenderedRow } from "./selection-view.js";

export type DecorationBox = Readonly<{ left: number; top: number; width: number; height: number }>;

export function rangeBoxes(range: LinkRange, rows: readonly RenderedRow[], cellWidth: number, container: HTMLElement): DecorationBox[] {
	const origin = container.getBoundingClientRect();
	const boxes: DecorationBox[] = [];
	for (const { box } of rows) {
		if (box.blockId !== range.blockId || box.row < range.startRow || box.row > range.endRow) continue;
		const left = box.row === range.startRow ? Math.min(range.startCell * cellWidth, box.width) : 0;
		const right = box.row === range.endRow ? Math.min(range.endCell * cellWidth, box.width) : box.width;
		if (right - left <= 0.5) continue;
		boxes.push({
			left: box.left + left - origin.left + container.scrollLeft,
			top: box.top - origin.top + container.scrollTop,
			width: right - left,
			height: box.bottom - box.top,
		});
	}
	return boxes;
}

export function paintBoxes(layer: HTMLElement, className: string, boxes: readonly DecorationBox[], labels?: readonly string[]): void {
	while (layer.children.length > boxes.length) layer.lastElementChild!.remove();
	for (let index = 0; index < boxes.length; index += 1) {
		let node = layer.children[index] as HTMLElement | undefined;
		if (!node) {
			node = document.createElement("div");
			layer.append(node);
		}
		node.className = className;
		const box = boxes[index]!;
		node.style.left = `${box.left}px`;
		node.style.top = `${box.top}px`;
		node.style.width = `${box.width}px`;
		node.style.height = `${box.height}px`;
		node.textContent = labels?.[index] ?? "";
	}
}
```

`styles.css` — after the `.terminal-block, .terminal-alt-surface { … cursor: default; }` rule:

```css
/* The hand appears only while a link is under the pointer, the way Warp swaps
   the cursor shape per hovered link (app/src/terminal/view.rs set_cursor_shape
   Cursor::PointingHand / reset_cursor; app/src/util/link_detection.rs). */
.terminal-link-hover .terminal-block,
.terminal-link-hover .terminal-alt-surface {
	cursor: pointer;
}

.terminal-decorations,
.terminal-decorations [data-terminal-layer] {
	position: absolute;
	top: 0;
	left: 0;
	width: 0;
	height: 0;
	overflow: visible;
	pointer-events: none;
}

.terminal-decorations {
	z-index: 2;
}

.terminal-decorations [data-terminal-layer] > div {
	position: absolute;
	box-sizing: border-box;
}

.terminal-link-underline {
	border-bottom: 1px solid var(--terminal-foreground);
}
```

(`styles.ts` inlines `styles.css` — `grep -n "styles.css" ts/renderer-dom/src/styles.ts`; if it imports the file, nothing else changes.)

`dom-block-renderer.ts`:
- imports: `Linkifier` from `./linkifier.js`; `DEFAULT_LINK_PROVIDERS, type DetectedLink, type LinkProvider` from `./link-providers.js`; `paintBoxes, rangeBoxes` from `./decorations.js`; `type TextRows` from `./selection-text.js`.
- fields:
  ```ts
  	private linkProviders: readonly LinkProvider[] = DEFAULT_LINK_PROVIDERS;
  	private readonly linkifier = new Linkifier({
  		rows: () => this.textRows(),
  		generation: () => this.core?.snapshot().generation ?? Number.NaN,
  		providers: () => this.linkProviders,
  		onChange: () => this.linkChanged(),
  	});
  	private decorationLayer: HTMLElement | null = null;
  	private readonly linkHoverListeners = new Set<(link: DetectedLink | null) => void>();
  ```
- `mount`, after the pinned header is inserted: `const decorations = document.createElement("div"); decorations.className = "terminal-decorations"; container.append(decorations); this.decorationLayer = decorations;`.
- a private `textRows()` that replaces the inline `snapshotTextRows(...)` call in `selectionView()`:
  ```ts
  	private textRows(): TextRows {
  		const core = this.core!;
  		return snapshotTextRows(core.snapshot(), this.currentFilter, this.decoder, (id) => core.linkUri(id));
  	}
  ```
- public API:
  ```ts
  	hoverAt(x: number, y: number): void {
  		if (!this.core) return;
  		this.linkifier.hover(this.pointAt(x, y));
  	}

  	clearHover(): void {
  		this.linkifier.hover(null);
  	}

  	hoveredLink(): DetectedLink | null {
  		return this.linkifier.current();
  	}

  	onLinkHover(listener: (link: DetectedLink | null) => void): () => void {
  		this.linkHoverListeners.add(listener);
  		return () => {
  			this.linkHoverListeners.delete(listener);
  		};
  	}

  	setLinkProviders(providers: readonly LinkProvider[]): void {
  		this.linkProviders = providers;
  		this.linkifier.refresh();
  	}
  ```
- private:
  ```ts
  	private linkChanged(): void {
  		const link = this.linkifier.current();
  		this.container?.classList.toggle("terminal-link-hover", link !== null);
  		this.paintDecorations();
  		for (const listener of [...this.linkHoverListeners]) listener(link);
  	}

  	private layer(name: string): HTMLElement | null {
  		const parent = this.decorationLayer;
  		if (!parent) return null;
  		let layer = parent.querySelector<HTMLElement>(`[data-terminal-layer="${name}"]`);
  		if (!layer) {
  			layer = document.createElement("div");
  			layer.dataset.terminalLayer = name;
  			parent.append(layer);
  		}
  		return layer;
  	}

  	private paintDecorations(): void {
  		const layer = this.layer("links");
  		const container = this.container;
  		if (!layer || !container) return;
  		const link = this.linkifier.current();
  		const boxes = link ? rangeBoxes(link.range, this.renderedRows(), this.cellMetrics().cellWidth, container) : [];
  		paintBoxes(layer, "terminal-link-underline", boxes);
  	}
  ```

  (Named sub-layers keep each affordance's boxes apart: Task 7 paints into `"hints"` and `"labels"`, Task 8 into `"redactions"`, each through `paintBoxes` on its own layer.)
- in `repaint`, on both exit paths (the alt branch and the end of the primary branch), right after `this.paintSelectionFill();`: `this.linkifier.refresh(); this.paintDecorations();`.
- `dispose()`: `this.linkifier.dispose(); this.decorationLayer = null; this.linkHoverListeners.clear();` and `this.container.classList.remove("terminal-link-hover");` inside the `if (this.container)` block.

`index.ts`: `export { DEFAULT_LINK_PROVIDERS, createPathProvider, type DetectedLink, type LinkProvider } from "./link-providers.js"; export type { LinkOs } from "./link-parsing.js"; export type { LinkRange } from "./logical-lines.js";`.

`ts/core/src/types.ts` `HostCapabilities` gains, after `listDirectory?`:

```ts
	resolvePath?(path: string, cwd: string): Promise<string | null>;
	openPath?(path: string, line?: number, column?: number): Promise<void>;
```

- [ ] **Step 7: `TerminalSurface` — pointer, click, providers**

`ts/react/src/selection-gesture.ts`:

```ts
export function linkModifierHeld(
	event: { metaKey: boolean; ctrlKey: boolean; shiftKey: boolean; altKey: boolean },
	mac: boolean,
): boolean {
	if (event.altKey || event.shiftKey) return false;
	return mac ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
}
```

`surface-geometry.ts`: `export function isWindowsPlatform(): boolean { return typeof navigator !== "undefined" && /Win/u.test(navigator.platform); }`.

`TerminalSurface.tsx`:
- imports: `linkModifierHeld` from `./selection-gesture.js`; `isWindowsPlatform` from `./surface-geometry.js`; `DEFAULT_LINK_PROVIDERS, createPathProvider, type DetectedLink` from `@operator/terminal-renderer-dom`.
- a providers effect, next to the features effect:
  ```tsx
  	const resolvePath = host?.resolvePath;
  	useLayoutEffect(() => {
  		const renderer = rendererRef.current;
  		if (!renderer) return;
  		if (!resolvePath) {
  			renderer.setLinkProviders(DEFAULT_LINK_PROVIDERS);
  			return;
  		}
  		const cwdOf = (blockId: string) => decodeBlocks(core.snapshot()).find((block) => block.id === blockId)?.cwd ?? "";
  		renderer.setLinkProviders([...DEFAULT_LINK_PROVIDERS, createPathProvider(resolvePath, cwdOf, isWindowsPlatform() ? "windows" : "posix")]);
  	}, [core, resolvePath]);
  ```
- in the mouse effect:
  ```ts
  		const activateLink = (link: DetectedLink) => {
  			const caps = hostCapsRef.current;
  			if (!caps) return;
  			if (link.kind === "path") {
  				if (link.path !== undefined) void caps.openPath?.(link.path, link.line, link.column);
  				return;
  			}
  			if (link.uri !== undefined) void caps.openLink(link.uri);
  		};
  		const onHoverMove = (event: MouseEvent) => {
  			if (pressOrigin) return;
  			renderer()?.hoverAt(event.clientX, event.clientY);
  		};
  		const onHoverLeave = () => renderer()?.clearHover();
  ```
  registered with `blockHost.addEventListener("mousemove", onHoverMove); blockHost.addEventListener("mouseleave", onHoverLeave);` and removed in the cleanup.
- `onMouseDown`, as its first statements after `compositionRef.current?.focus(); const button = buttonOf(event); if (button === null) return;`:
  ```ts
  			if (button === 0 && linkModifierHeld(event, isMacPlatform())) {
  				renderer()?.hoverAt(event.clientX, event.clientY);
  				const link = renderer()?.hoveredLink();
  				if (link) {
  					event.preventDefault();
  					activateLink(link);
  					return;
  				}
  			}
  ```
  (this sits before the mouse-report branch on purpose: a modifier press on a link opens it even under a program that tracks the mouse, as Warp and VS Code do; `hoverAt` before `hoveredLink` makes the press see the cell it lands on rather than the last move).

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS, including the Step 2 tests.

A synchronous `hoveredLink()` right after `hoverAt()` returns the *previous* resolution when the line's providers have not resolved yet (the first hover on a line); the pointer move that preceded the press has almost always resolved it. The mouse test's `setTimeout(0)` wait after the move is what stands in for that.

- [ ] **Step 8: The harness and the affordance gate**

`bench/agent-session/main.ts`: add to the `AgentSession` type and the exported object (import `type DetectedLink`, `createPathProvider`, `DEFAULT_LINK_PROVIDERS` from `@operator/terminal-renderer-dom`):

```ts
	hoverCell(row: number, cell: number): Promise<{ x: number; y: number }>;
	clearHover(): void;
	hoveredLink(): DetectedLink | null;
	enablePathLinks(suffixes: string[]): void;
```

```ts
	hoverCell: async (row, cell) => {
		const label = core.snapshot().firstStableRow + row;
		const node = host.querySelector<HTMLElement>(`[data-terminal-row="${label}"]`);
		if (!node) throw new Error(`row ${row} is not rendered`);
		const rect = node.getBoundingClientRect();
		const { cellWidth, cellHeight } = domRenderer.measure();
		const x = rect.left + (cell + 0.5) * cellWidth;
		const y = rect.top + cellHeight / 2;
		domRenderer.hoverAt(x, y);
		await new Promise((resolve) => setTimeout(resolve, 50));
		return { x, y };
	},
	clearHover: () => domRenderer.clearHover(),
	hoveredLink: () => domRenderer.hoveredLink(),
	enablePathLinks: (suffixes) => {
		domRenderer.setLinkProviders([
			...DEFAULT_LINK_PROVIDERS,
			createPathProvider(async (path) => (suffixes.some((suffix) => path.endsWith(suffix)) ? `/probe/${path}` : null), () => "", "posix"),
		]);
	},
```

`session-api.test.mjs`: the name list gains `"hoverCell", "clearHover", "hoveredLink", "enablePathLinks"`.

`bench/agent-session/affordance-gate.mjs`:

```js
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const baselinesDir = path.join(agentDir, "baselines", "act-probe");
const argv = process.argv.slice(2);
const action = argv.includes("--action") ? argv[argv.indexOf("--action") + 1] : undefined;
if (!action) {
	process.stderr.write("usage: affordance-gate.mjs --action <hover|hint|redact>\n");
	process.exit(2);
}

const actions = {
	async hover(page, shoot) {
		const report = [];
		for (const [name, row, cell, suffixes] of [
			["hover-url", 0, 10, null],
			["hover-osc8", 1, 8, null],
			["hover-wrapped", 3, 5, null],
			["hover-path", 0, 40, [".ts", ".go"]],
		]) {
			if (suffixes) await page.evaluate((list) => window.__agentSession.enablePathLinks(list), suffixes);
			await page.evaluate(([r, c]) => window.__agentSession.hoverCell(r, c), [row, cell]);
			await page.waitForTimeout(150);
			const link = await page.evaluate(() => window.__agentSession.hoveredLink());
			report.push([name, link?.kind ?? null, link?.uri ?? link?.path ?? null]);
			await shoot(name);
			await page.evaluate(() => window.__agentSession.clearHover());
		}
		return report;
	},
};

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=act-probe&dir=probes`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	await page.waitForTimeout(300);
	const outDir = path.join(baselinesDir, `affordance-${action}`);
	await mkdir(outDir, { recursive: true });
	const shoot = async (name) => {
		await writeFile(path.join(outDir, `${name}.png`), await page.screenshot({ type: "png", animations: "disabled", caret: "hide" }));
		process.stdout.write(`side-by-side act-probe/affordance-${action}/${name}.png (compare with act-probe/offset-0.png)\n`);
	};
	const run = actions[action];
	if (!run) throw new Error(`unknown action ${action}`);
	const report = await run(page, shoot);
	process.stdout.write(`${JSON.stringify({ action, report })}\n`);
	await page.close();
} finally {
	await browser?.close();
	await server.close();
}
```

`package.json` scripts: `"bench:affordances": "node ./bench/agent-session/affordance-gate.mjs"`.

Run `node --test ./bench/agent-session/session-api.test.mjs` → PASS. Run `npm run bench:affordances -- --action hover` → four `side-by-side …` lines and a report whose kinds are `["hover-url","url","https://example.com/docs"]`, `["hover-osc8","hyperlink","https://example.org/x"]`, `["hover-wrapped","url","https://example.com/aaa…/end"]`, `["hover-path","path","/probe/src/app/main.ts"]`. Open the four PNGs: one underline under the URL; one under "the linked text"; one spanning both rows of the wrapped line; one under `src/app/main.ts:42`. A `null` kind in the report is a failure of this task, not a screenshot problem.

- [ ] **Step 9: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `node --test ./bench/agent-session/fixtures.test.mjs ./bench/agent-session/session-api.test.mjs` → PASS.
- `npm run bench:selection` → PASS (the row DOM gained no node; the decoration layer is a container child).
- `npm run bench:feel` → `PASS feel gate: zero pixel diff` (no pointer in the gate; the act-probe baseline recorded in Step 1 is now diffed too).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean (the new capability members are optional).

CHANGELOG:

```markdown
- renderer-dom/react: hovering the transcript underlines the link under the pointer and swaps the arrow for a hand only there (Warp `app/src/terminal/view.rs`); a press with the platform modifier (Cmd on macOS, Ctrl elsewhere) opens it — `HostCapabilities.openLink` for a URL or an OSC 8 hyperlink, the new optional `HostCapabilities.openPath(path, line?, column?)` for a file. Links are found per hovered logical line by providers in priority order (xterm.js `src/browser/Linkifier.ts`): OSC 8 runs, then xterm.js's strict `https?` grammar, then — only when the host supplies `HostCapabilities.resolvePath(path, cwd)` — VS Code's `file:line:col` grammar validated against the host's file system. Nothing paints without a pointer; the feel gate is unchanged. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-hover/`.
- bench: the `act-probe` fixture (URLs, an OSC 8 link, a soft-wrapped URL, `path:line` references, token-shaped strings, diff headers, hashes) and `npm run bench:affordances -- --action <name>`, which drives one affordance through the harness page and records screenshots beside the probe's baseline, never diffed.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts packages/terminal/bench packages/terminal/package.json packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: linkifier — hover providers, underline overlay, modifier click, pointing hand; act-probe fixture and the affordance gate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Hint mode — the chord, the rule set, the labels, `onHint`

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/{hint-rules.ts,hint-rules.test.ts,hint-labels.ts,hint-labels.test.ts,hint-mode.ts,hint-mode.test.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,index.ts}`
- Modify: `packages/terminal/ts/react/src/{selection-gesture.ts,selection-gesture.test.ts,TerminalSurface.tsx}`, create `packages/terminal/ts/react/src/TerminalSurface.hint.test.tsx`
- Modify: `packages/terminal/ts/editor/src/encode-key.test.ts` (pin plain Ctrl+Space; the encoder itself is unchanged)
- Modify: `packages/terminal/bench/agent-session/{main.ts,affordance-gate.mjs,session-api.test.mjs}`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `logicalLineAt`, `LinkRange`, `rangeContains` (Task 6), `rangeBoxes`/`paintBoxes` and the named decoration sub-layers (Task 6), `TextRows` (Tasks 1/6), `renderedRows`/`filteredBlocks`/`cellMetrics` (`dom-block-renderer.ts`), the alt-screen `onKeyDown` (`TerminalSurface.tsx:239`) and the editor's `keydown` listeners (`TerminalSurface.tsx:505-512`, `ts/editor/src/line-editor.ts:70`).
- Produces: the "Hint mode" shapes above. Task 9 maps `onHint` to Operator actions.

The chord is Ctrl+Shift+Space, WezTerm's own default (`wezterm-gui/src/commands.rs:828`), on every platform. **It is not free**: `encodeKey`'s control branch is `ctrlKey && !altKey` and ignores `shiftKey` (`ts/editor/src/encode-key.ts:111-115`), so Ctrl+Shift+Space encodes `controlCode(" ")` = `\x00` today, exactly as Ctrl+Space does. Taking the chord stops the **shifted** form reaching the pty; plain Ctrl+Space — the emacs set-mark key readline binds — keeps sending `\x00`, and Step 3 pins that. Nothing else in the encoder distinguishes the two, so this is the whole cost. While hint mode is active the surface swallows every key: a printable character narrows the label set, Backspace un-types, Escape and any other key cancel, and nothing reaches the pty. Labels come from WezTerm's `compute_labels_for_alphabet` (`quickselect.rs:57-100`, tmux-thumbs' algorithm) over `DEFAULT_HINT_ALPHABET`, assigned from the bottom-right match backwards so the nearest match gets the shortest label, and shared by matches whose text is identical (WezTerm's `match_id`).

- [ ] **Step 1: Write the failing rule and label tests**

`hint-labels.test.ts` — the table is WezTerm's own `alphabet_test` module (`quickselect.rs:133-195`), ported case for case:

```ts
import { describe, expect, it } from "vitest";
import { computeLabelsForAlphabet, DEFAULT_HINT_ALPHABET } from "./hint-labels";

// wezterm/wezterm-gui/src/overlay/quickselect.rs mod alphabet_test
describe("computeLabelsForAlphabet", () => {
	it("simple_alphabet", () => {
		expect(computeLabelsForAlphabet("abcd", 3)).toEqual(["a", "b", "c"]);
	});
	it("more_matches_than_alphabet_can_represent", () => {
		expect(computeLabelsForAlphabet("asdfqwerzxcvjklmiuopghtybn", 792)).toHaveLength(676);
	});
	it("composed_single", () => {
		expect(computeLabelsForAlphabet("abcd", 6)).toEqual(["a", "b", "c", "da", "db", "dc"]);
	});
	it("composed_multiple", () => {
		expect(computeLabelsForAlphabet("abcd", 8)).toEqual(["a", "b", "ca", "cb", "da", "db", "dc", "dd"]);
	});
	it("composed_max", () => {
		expect(computeLabelsForAlphabet("ab", 5)).toEqual(["aa", "ab", "ba", "bb"]);
	});
	it("lowercases the alphabet", () => {
		expect(computeLabelsForAlphabet("AB", 4)).toEqual(["aa", "ab", "ba", "bb"]);
	});
	it("ships wezterm's default alphabet", () => {
		expect(DEFAULT_HINT_ALPHABET).toBe("asdfqwerzxcvjklmiuopghtybn");
	});
	it("returns nothing for no matches", () => {
		expect(computeLabelsForAlphabet("abc", 0)).toEqual([]);
	});
});
```

`hint-rules.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { DEFAULT_HINT_RULES, fileLineFields } from "./hint-rules";

function matchOf(id: string, text: string): { text: string; start: number } | null {
	const rule = DEFAULT_HINT_RULES.find((candidate) => candidate.id === id)!;
	const regex = new RegExp(rule.regex.source, rule.regex.flags);
	const match = regex.exec(text);
	if (!match) return null;
	const picked = rule.capture === "last" ? [...match].reverse().find((group, index) => group !== undefined && index < match.length - 1) ?? match[0] : match[0];
	return { text: picked, start: match.index + match[0].indexOf(picked) };
}

describe("DEFAULT_HINT_RULES", () => {
	it("carries wezterm's set minus ipfs, plus kitty's path:line, file-line first", () => {
		expect(DEFAULT_HINT_RULES.map((rule) => rule.id)).toEqual([
			"file-line", "markdown-url", "url", "diff-a", "diff-b", "docker", "path", "color", "uuid", "sha", "ip", "ipv6", "address", "number",
		]);
		expect(DEFAULT_HINT_RULES.every((rule) => rule.regex.flags.includes("g"))).toBe(true);
	});
	it("matches what each rule is for", () => {
		expect(matchOf("url", "see https://x.y/a here")?.text).toBe("https://x.y/a");
		expect(matchOf("url", "git@github.com:o/r.git")?.text).toBe("git@github.com:o/r.git");
		expect(matchOf("markdown-url", "[docs](https://x.y/md)")?.text).toBe("https://x.y/md");
		expect(matchOf("diff-a", "--- a/foo/bar.ts")?.text).toBe("foo/bar.ts");
		expect(matchOf("diff-b", "+++ b/foo/bar.ts")?.text).toBe("foo/bar.ts");
		expect(matchOf("docker", `sha256:${"c".repeat(64)}`)?.text).toBe("c".repeat(64));
		expect(matchOf("path", "edit src/app/main.ts now")?.text).toBe("src/app/main.ts");
		expect(matchOf("color", "bg #ff8800;")?.text).toBe("#ff8800");
		expect(matchOf("uuid", "id 123e4567-e89b-12d3-a456-426614174000")?.text).toBe("123e4567-e89b-12d3-a456-426614174000");
		expect(matchOf("sha", "at 0123456789abcdef done")?.text).toBe("0123456789abcdef");
		expect(matchOf("ip", "from 10.0.0.1:8080")?.text).toBe("10.0.0.1");
		expect(matchOf("address", "at 0xdeadbeef")?.text).toBe("0xdeadbeef");
		expect(matchOf("number", "took 123456 ms")?.text).toBe("123456");
		expect(matchOf("file-line", "at src/a.ts:42 line")?.text).toBe("src/a.ts:42");
		expect(DEFAULT_HINT_RULES.find((rule) => rule.id === "ipfs")).toBeUndefined();
	});
});

describe("fileLineFields", () => {
	it("splits kitty's named groups and a trailing :N, and expands a leading tilde", () => {
		const regex = new RegExp(DEFAULT_HINT_RULES[0]!.regex.source, "u");
		expect(fileLineFields(regex.exec("src/a.ts:42")!)).toEqual({ path: "src/a.ts", line: 42 });
		expect(fileLineFields(regex.exec("~/x/y.go:7")!)).toEqual({ path: "~/x/y.go", line: 7 });
	});
});
```

`hint-mode.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { collectHintMatches, HintSession } from "./hint-mode";
import { DEFAULT_HINT_RULES } from "./hint-rules";
import { logicalLineAt } from "./logical-lines";
import type { TextRows } from "./selection-text";

function lines(...texts: string[]) {
	const rows: TextRows = {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => texts.length,
		rowText: (_id, row) => texts[row] ?? "",
		rowSpans: () => [],
		rowWrapped: () => false,
	};
	return texts.map((_text, row) => logicalLineAt(rows, "b", row)!);
}

describe("collectHintMatches", () => {
	it("finds every rule's matches in order and does not overlap them", () => {
		const matches = collectHintMatches(lines("open https://x.y/a and src/a.ts:42 now"), DEFAULT_HINT_RULES);
		expect(matches.map((match) => [match.ruleId, match.text])).toEqual([
			["url", "https://x.y/a"],
			["file-line", "src/a.ts:42"],
		]);
		expect(matches[1]).toMatchObject({ path: "src/a.ts", line: 42 });
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 18 });
	});
	it("prefers path:line over the bare path at the same start", () => {
		const matches = collectHintMatches(lines("src/a.ts:42"), DEFAULT_HINT_RULES);
		expect(matches.map((match) => match.ruleId)).toEqual(["file-line"]);
	});
	it("spans a wrapped logical line as one candidate", () => {
		const rows: TextRows = {
			blockIds: ["b"],
			firstRow: () => 0,
			rowCount: () => 2,
			rowText: (_id, row) => (row === 0 ? "go https://x.y/aaa" : "bbb done"),
			rowSpans: () => [],
			rowWrapped: (_id, row) => row === 0,
		};
		const matches = collectHintMatches([logicalLineAt(rows, "b", 0)!], DEFAULT_HINT_RULES);
		expect(matches[0]!.text).toBe("https://x.y/aaabbb");
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 3, endRow: 1, endCell: 3 });
	});
});

describe("HintSession", () => {
	const match = (text: string) => ({ ruleId: "url", text, range: { blockId: "b", startRow: 0, startCell: 0, endRow: 0, endCell: 1 } });

	it("labels from the last match backwards and shares a label between identical texts", () => {
		const session = new HintSession([match("one"), match("two"), match("one")], "abcd");
		expect(session.labelled().map((entry) => [entry.label, entry.match.text])).toEqual([
			["b", "one"],
			["a", "two"],
			["b", "one"],
		]);
	});
	it("narrows on typed characters, un-types on backspace and resolves a full label", () => {
		const session = new HintSession(Array.from({ length: 6 }, (_v, index) => match(`m${index}`)), "abcd");
		expect(session.labelled().map((entry) => entry.label)).toEqual(["dc", "db", "da", "c", "b", "a"]);
		expect(session.type("d")).toBeNull();
		expect(session.typed()).toBe("d");
		expect(session.labelled().map((entry) => entry.label)).toEqual(["dc", "db", "da"]);
		session.backspace();
		expect(session.typed()).toBe("");
		expect(session.labelled()).toHaveLength(6);
		expect(session.type("a")?.text).toBe("m5");
	});
	it("resets the typed prefix when a character matches no label", () => {
		const session = new HintSession([match("only")], "abcd");
		expect(session.type("z")).toBeNull();
		expect(session.typed()).toBe("");
		expect(session.labelled()).toHaveLength(1);
	});
});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/hint-labels.test.ts src/hint-rules.test.ts src/hint-mode.test.ts` → FAIL, modules not found.

- [ ] **Step 2: Implement the rules, the labels and the session**

`hint-labels.ts`:

```ts
// wezterm/wezterm-gui/src/overlay/quickselect.rs compute_labels_for_alphabet
// (derived from tmux-thumbs, MIT, Copyright (c) 2019 Ferran Basora)
// wezterm/config/src/config.rs default_alphabet
export const DEFAULT_HINT_ALPHABET = "asdfqwerzxcvjklmiuopghtybn";

export function computeLabelsForAlphabet(alphabet: string, count: number): string[] {
	const letters = [...alphabet].map((letter) => letter.toLowerCase());
	const primary = [...letters];
	const secondary: string[] = [];
	while (primary.length + secondary.length < count) {
		const prefix = primary.pop();
		if (prefix === undefined) break;
		const take = count - primary.length - secondary.length;
		secondary.unshift(...letters.slice(0, Math.max(take, 0)).map((letter) => `${prefix}${letter}`));
	}
	return [...primary.slice(0, Math.max(count - secondary.length, 0)), ...secondary];
}
```

`hint-rules.ts`:

```ts
export type HintRule = Readonly<{ id: string; regex: RegExp; capture: "whole" | "last" }>;

export const HINT_RULE_HYPERLINK = "hyperlink";

// kitty/kittens/hints/marks.go:31-41 (FILE_EXTENSION, path_regex, default_linenum_regex)
const FILE_EXTENSION = String.raw`\.(?:[a-zA-Z0-9]{2,7}|[ahcmo])(?:\b|[^.])`;
const KITTY_PATH = String.raw`(?:\S*?/[\r\S]+)|(?:\S[\r\S]*${FILE_EXTENSION})\b`;

// wezterm/wezterm-gui/src/overlay/quickselect.rs:26-56 PATTERNS, minus ipfs
export const DEFAULT_HINT_RULES: readonly HintRule[] = [
	{ id: "file-line", regex: new RegExp(String.raw`(?<path>${KITTY_PATH}):(?<line>\d+)`, "gu"), capture: "whole" },
	{ id: "markdown-url", regex: /\[[^\]]*\]\(([^)]+)\)/gu, capture: "last" },
	{ id: "url", regex: /(?:https?:\/\/|git@|git:\/\/|ssh:\/\/|ftp:\/\/|file:\/\/)\S+/gu, capture: "whole" },
	{ id: "diff-a", regex: /--- a\/(\S+)/gu, capture: "last" },
	{ id: "diff-b", regex: /\+\+\+ b\/(\S+)/gu, capture: "last" },
	{ id: "docker", regex: /sha256:([0-9a-f]{64})/gu, capture: "last" },
	{ id: "path", regex: /(?:[.\w\-@~]+)?(?:\/+[.\w\-@]+)+/gu, capture: "whole" },
	{ id: "color", regex: /#[0-9a-fA-F]{6}/gu, capture: "whole" },
	{ id: "uuid", regex: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gu, capture: "whole" },
	{ id: "sha", regex: /[0-9a-f]{7,40}/gu, capture: "whole" },
	{ id: "ip", regex: /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/gu, capture: "whole" },
	{ id: "ipv6", regex: /[A-Fa-f0-9:]+:+[A-Fa-f0-9:]+[%\w\d]+/gu, capture: "whole" },
	{ id: "address", regex: /0x[0-9a-fA-F]+/gu, capture: "whole" },
	{ id: "number", regex: /[0-9]{4,}/gu, capture: "whole" },
];

// kitty/kittens/hints/marks.go:157-166 linenum_group_processor
export function fileLineFields(match: RegExpExecArray): { path: string; line: number } | null {
	const path = match.groups?.path;
	const line = match.groups?.line;
	if (path === undefined || line === undefined) return null;
	const trailing = /:(\d+)$/u.exec(path);
	if (trailing) return { path: path.slice(0, trailing.index), line: Number(trailing[1]) };
	return { path, line: Number(line) };
}
```

`hint-mode.ts`:

```ts
import { computeLabelsForAlphabet, DEFAULT_HINT_ALPHABET } from "./hint-labels.js";
import { fileLineFields, type HintRule } from "./hint-rules.js";
import type { LinkRange, LogicalLineView } from "./logical-lines.js";

export type HintMatch = Readonly<{ ruleId: string; text: string; path?: string; line?: number; range: LinkRange }>;
export type HintEvent = Readonly<{ ruleId: string; text: string; path?: string; line?: number }>;

export function collectHintMatches(lines: readonly LogicalLineView[], rules: readonly HintRule[]): HintMatch[] {
	const out: HintMatch[] = [];
	for (const line of lines) {
		const taken: Array<readonly [number, number]> = [];
		const found: HintMatch[] = [];
		for (const rule of rules) {
			const regex = new RegExp(rule.regex.source, rule.regex.flags.includes("g") ? rule.regex.flags : `${rule.regex.flags}g`);
			for (const match of line.text.matchAll(regex)) {
				const whole = match[0];
				const wholeStart = match.index ?? 0;
				let text = whole;
				let start = wholeStart;
				if (rule.capture === "last") {
					for (let group = match.length - 1; group >= 1; group -= 1) {
						if (match[group] === undefined) continue;
						text = match[group]!;
						start = wholeStart + whole.indexOf(text);
						break;
					}
				}
				const end = start + text.length;
				if (taken.some(([from, to]) => start < to && from < end)) continue;
				taken.push([wholeStart, wholeStart + whole.length]);
				const fields = rule.id === "file-line" ? fileLineFields(match as RegExpExecArray) : null;
				found.push({ ruleId: rule.id, text, path: fields?.path, line: fields?.line, range: line.rangeOf(start, end) });
			}
		}
		found.sort((a, b) => a.range.startRow - b.range.startRow || a.range.startCell - b.range.startCell);
		out.push(...found);
	}
	return out;
}

export class HintSession {
	private readonly labels: string[];
	private prefix = "";

	constructor(
		private readonly matches: readonly HintMatch[],
		alphabet: string = DEFAULT_HINT_ALPHABET,
	) {
		const byText = new Map<string, number>();
		for (let index = matches.length - 1; index >= 0; index -= 1) {
			const text = matches[index]!.text;
			if (!byText.has(text)) byText.set(text, byText.size);
		}
		const pool = computeLabelsForAlphabet(alphabet, byText.size);
		this.labels = matches.map((match) => pool[byText.get(match.text)!] ?? "");
	}

	labelled(): readonly { label: string; match: HintMatch }[] {
		return this.matches
			.map((match, index) => ({ label: this.labels[index]!, match }))
			.filter((entry) => entry.label !== "" && entry.label.startsWith(this.prefix));
	}

	type(character: string): HintMatch | null {
		const next = this.prefix + character.toLowerCase();
		const exact = this.labels.findIndex((label) => label === next);
		if (exact >= 0) {
			this.prefix = "";
			return this.matches[exact]!;
		}
		this.prefix = this.labels.some((label) => label.startsWith(next)) ? next : "";
		return null;
	}

	backspace(): void {
		this.prefix = this.prefix.slice(0, -1);
	}

	typed(): string {
		return this.prefix;
	}
}
```

Run: `npx vitest run src/hint-labels.test.ts src/hint-rules.test.ts src/hint-mode.test.ts` → PASS.

- [ ] **Step 3: Failing renderer and surface tests**

Add to `dom-block-renderer.test.ts`:

```ts
	it("labels every visible match on the chord, narrows on a typed character, and emits the hint", async () => {
		const { host, renderer } = mountWith("go https://x.y/a then src/a.ts:42\r\n");
		await flushRepaint();
		expect(renderer.hintBegin()).toBe(2);
		expect(renderer.hintActive()).toBe(true);
		const labels = [...host.querySelectorAll(".terminal-hint-label")].map((node) => node.textContent);
		expect(labels).toEqual(["s", "a"]);
		expect(host.querySelectorAll(".terminal-hint-match")).toHaveLength(2);
		expect(renderer.hintType("a")).toEqual({ ruleId: "file-line", text: "src/a.ts:42", path: "src/a.ts", line: 42 });
		expect(renderer.hintActive()).toBe(false);
		expect(host.querySelectorAll(".terminal-hint-label")).toHaveLength(0);
	});

	it("cancelling hint mode removes every label and paints nothing", async () => {
		const { host, renderer } = mountWith("go https://x.y/a\r\n");
		await flushRepaint();
		renderer.hintBegin();
		expect(host.querySelectorAll(".terminal-hint-label").length).toBeGreaterThan(0);
		renderer.hintCancel();
		expect(host.querySelectorAll(".terminal-hint-label")).toHaveLength(0);
		expect(host.querySelectorAll(".terminal-hint-match")).toHaveLength(0);
		expect(renderer.hintActive()).toBe(false);
	});
```

`packages/terminal/ts/react/src/TerminalSurface.hint.test.tsx`:

```tsx
import { act, cleanup } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { feed, flushRepaint, loadWasm, renderSurface } from "./surface-harness";

function key(target: EventTarget, init: KeyboardEventInit): KeyboardEvent {
	const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init });
	target.dispatchEvent(event);
	return event;
}

describe("TerminalSurface hint mode", () => {
	beforeAll(loadWasm);
	afterEach(() => cleanup());

	it("enters on the chord, emits onHint for a typed label, and sends nothing to the pty", async () => {
		const onSendRaw = vi.fn();
		const onHint = vi.fn();
		const { container, core } = renderSurface({ onSendRaw, onHint });
		act(() => { feed(core, "see https://x.y/a now\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		const chord = key(surface, { key: " ", code: "Space", ctrlKey: true, shiftKey: true });
		expect(chord.defaultPrevented).toBe(true);
		const typed = key(surface, { key: "a" });
		expect(typed.defaultPrevented).toBe(true);
		expect(onHint).toHaveBeenCalledWith({ ruleId: "url", text: "https://x.y/a" });
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("escape cancels and the next key reaches the pty again", async () => {
		const onSendRaw = vi.fn();
		const onHint = vi.fn();
		const { container, core } = renderSurface({ onSendRaw, onHint });
		act(() => { feed(core, "\x1b[?1049hsee https://x.y/a now\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		key(surface, { key: " ", code: "Space", ctrlKey: true, shiftKey: true });
		onSendRaw.mockClear();
		key(surface, { key: "Escape" });
		expect(onHint).not.toHaveBeenCalled();
		expect(onSendRaw).not.toHaveBeenCalled();
		key(surface, { key: "x" });
		expect(onSendRaw).toHaveBeenCalledWith("x");
	});

	it("leaves plain Ctrl+Space alone so readline still gets its NUL", async () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => { feed(core, "\x1b[?1049hidle\r\n"); });
		await flushRepaint();
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		key(surface, { key: " ", code: "Space", ctrlKey: true });
		expect(onSendRaw).toHaveBeenCalledWith("\x00");
	});
});
```

(`renderSurface` gains `onHint?: (hint: HintEvent) => void;` in its overrides and passes it through, beside `onPaint`.)

Add to `ts/editor/src/encode-key.test.ts`, beside the existing `\x00` case at `:42`, so the key the chord consumes is pinned before it is taken:

```ts
	it("keeps plain Ctrl+Space as NUL; only the shifted form is the hint chord", () => {
		expect(encodeKey(key({ key: " ", ctrlKey: true }))).toBe("\x00");
		expect(encodeKey(key({ key: " ", ctrlKey: true, shiftKey: true }))).toBe("\x00");
	});
```

(both still encode `\x00` at this layer — the surface's capture-phase handler is what stops the shifted one before `encodeKey` is reached, which the `TerminalSurface.hint.test.tsx` case below proves by asserting `onSendRaw` was never called.)

Add to `selection-gesture.test.ts`:

```ts
describe("isHintChord", () => {
	it("is ctrl+shift+space and nothing else", () => {
		expect(isHintChord({ key: " ", code: "Space", ctrlKey: true, shiftKey: true, metaKey: false, altKey: false })).toBe(true);
		expect(isHintChord({ key: " ", code: "Space", ctrlKey: true, shiftKey: false, metaKey: false, altKey: false })).toBe(false);
		expect(isHintChord({ key: "a", code: "KeyA", ctrlKey: true, shiftKey: true, metaKey: false, altKey: false })).toBe(false);
		expect(isHintChord({ key: " ", code: "Space", ctrlKey: true, shiftKey: true, metaKey: true, altKey: false })).toBe(false);
	});
});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/dom-block-renderer.test.ts -t hint` → FAIL, `hintBegin` is not a function. `cd ../react && npx vitest run src/TerminalSurface.hint.test.tsx src/selection-gesture.test.ts` → FAIL.

- [ ] **Step 4: Implement in the renderer**

`styles.css`, after `.terminal-link-underline`:

```css
/* Alacritty paints a hint's match and its label over the cells the match
   occupies (alacritty/src/display/hint.rs, HintState::labels); the label sits
   at the match's first cell so the eye reads label-then-text. */
.terminal-hint-match {
	background: var(--terminal-selection);
}

.terminal-hint-label {
	display: flex;
	align-items: center;
	padding: 0 2px;
	width: auto;
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: 700;
	line-height: var(--terminal-line-height);
	color: var(--terminal-background);
	background: var(--terminal-ansi-3);
}
```

`dom-block-renderer.ts`:
- imports: `collectHintMatches, HintSession, type HintEvent, type HintMatch` from `./hint-mode.js`; `DEFAULT_HINT_RULES, type HintRule` from `./hint-rules.js`; `logicalLineAt` from `./logical-lines.js`.
- field `private hint: HintSession | null = null;`
- public API:
  ```ts
  	hintBegin(rules: readonly HintRule[] = DEFAULT_HINT_RULES): number {
  		const core = this.core;
  		if (!core) return 0;
  		const rows = this.textRows();
  		const seen = new Set<string>();
  		const lines = [];
  		for (const { box } of this.renderedRows()) {
  			const line = logicalLineAt(rows, box.blockId, box.row);
  			if (!line) continue;
  			const key = `${line.blockId}:${line.firstRow}`;
  			if (seen.has(key)) continue;
  			seen.add(key);
  			lines.push(line);
  		}
  		const matches = collectHintMatches(lines, rules);
  		this.hint = matches.length > 0 ? new HintSession(matches) : null;
  		this.paintHints();
  		return matches.length;
  	}

  	hintType(character: string): HintEvent | null {
  		const session = this.hint;
  		if (!session) return null;
  		const match = session.type(character);
  		if (!match) {
  			this.paintHints();
  			return null;
  		}
  		this.hintCancel();
  		return { ruleId: match.ruleId, text: match.text, path: match.path, line: match.line };
  	}

  	hintBackspace(): void {
  		this.hint?.backspace();
  		this.paintHints();
  	}

  	hintCancel(): void {
  		this.hint = null;
  		this.paintHints();
  	}

  	hintActive(): boolean {
  		return this.hint !== null;
  	}
  ```
- private:
  ```ts
  	private paintHints(): void {
  		const matchLayer = this.layer("hints");
  		const labelLayer = this.layer("labels");
  		const container = this.container;
  		if (!matchLayer || !labelLayer || !container) return;
  		const entries = this.hint?.labelled() ?? [];
  		const rows = this.renderedRows();
  		const { cellWidth, cellHeight } = this.cellMetrics();
  		const matchBoxes = [];
  		const labelBoxes = [];
  		const labels: string[] = [];
  		for (const entry of entries) {
  			const boxes = rangeBoxes(entry.match.range, rows, cellWidth, container);
  			if (boxes.length === 0) continue;
  			matchBoxes.push(...boxes);
  			labelBoxes.push({ ...boxes[0]!, width: Math.max(entry.label.length, 1) * cellWidth, height: cellHeight });
  			labels.push(entry.label);
  		}
  		paintBoxes(matchLayer, "terminal-hint-match", matchBoxes);
  		paintBoxes(labelLayer, "terminal-hint-label", labelBoxes, labels);
  	}
  ```
- `repaint`, beside `this.paintDecorations();` on both exit paths: `this.paintHints();`.
- `dispose()`: `this.hint = null;`.

`index.ts`: `export { DEFAULT_HINT_RULES, type HintRule } from "./hint-rules.js"; export { DEFAULT_HINT_ALPHABET } from "./hint-labels.js"; export type { HintEvent, HintMatch } from "./hint-mode.js";`.

Run: `npx vitest run src/dom-block-renderer.test.ts -t hint` → PASS. (The two-match label expectation `["s","a"]` is `computeLabelsForAlphabet(DEFAULT_HINT_ALPHABET, 2)` = `["a","s"]`, assigned last-match-first: the file-line match gets `a`, the URL gets `s`. If the labels come out the other way round the bottom-first assignment did not land.)

- [ ] **Step 5: Implement the chord in `TerminalSurface`**

`selection-gesture.ts`:

```ts
// wezterm/wezterm-gui/src/commands.rs:828 (QuickSelect default key)
export function isHintChord(event: { key: string; code: string; ctrlKey: boolean; shiftKey: boolean; metaKey: boolean; altKey: boolean }): boolean {
	if (!event.ctrlKey || !event.shiftKey || event.metaKey || event.altKey) return false;
	return event.code === "Space" || event.key === " ";
}
```

`TerminalSurface.tsx`:
- prop `onHint?: (hint: HintEvent) => void;` (import the type from `@operator/terminal-renderer-dom`), a ref `onHintRef` like `onPaintRef`.
- one capture-phase key handler bound in the mouse/keyboard effect, so it runs before the editor's and the alt screen's listeners:
  ```ts
  		const onHintKey = (event: KeyboardEvent) => {
  			const target = renderer();
  			if (!target) return;
  			if (!target.hintActive()) {
  				if (!isHintChord(event)) return;
  				event.preventDefault();
  				event.stopPropagation();
  				target.hintBegin();
  				return;
  			}
  			event.preventDefault();
  			event.stopPropagation();
  			if (event.key === "Escape") {
  				target.hintCancel();
  				return;
  			}
  			if (event.key === "Backspace") {
  				target.hintBackspace();
  				return;
  			}
  			if (event.key.length !== 1 || event.metaKey || event.ctrlKey || event.altKey) {
  				target.hintCancel();
  				return;
  			}
  			const hint = target.hintType(event.key);
  			if (hint) onHintRef.current?.(hint);
  		};
  ```
  registered as `surface?.addEventListener("keydown", onHintKey, true);` with the matching `removeEventListener(..., true)` in the cleanup. The capture phase on the *surface* element covers both input paths: the editor host and the alt-screen block host are inside it.
- `renderSurface` in `surface-harness.tsx` gains `onHint` in its overrides and passes it to `<TerminalSurface />`.

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 6: The harness action and the screenshot**

`bench/agent-session/main.ts`: add `hintBegin(): number; hintType(character: string): unknown; hintCancel(): void;` to the `AgentSession` type and `hintBegin: () => domRenderer.hintBegin(), hintType: (character) => domRenderer.hintType(character), hintCancel: () => domRenderer.hintCancel(),` to the object. `session-api.test.mjs`: the name list gains `"hintBegin", "hintType", "hintCancel"`.

`affordance-gate.mjs` — add to `actions`:

```js
	async hint(page, shoot) {
		const count = await page.evaluate(() => window.__agentSession.hintBegin());
		await page.waitForTimeout(100);
		await shoot("hint-all");
		const labels = await page.evaluate(() => [...document.querySelectorAll(".terminal-hint-label")].map((node) => node.textContent));
		await page.evaluate(() => window.__agentSession.hintType(document.querySelector(".terminal-hint-label")?.textContent?.[0] ?? "a"));
		await page.waitForTimeout(100);
		await shoot("hint-narrowed");
		await page.evaluate(() => window.__agentSession.hintCancel());
		return [["hint-count", count, labels.slice(0, 8).join(",")]];
	},
```

Run `npm run bench:affordances -- --action hint` → two `side-by-side …` lines and a report with a non-zero count and the first labels. Open `hint-all.png`: every URL, path, sha, uuid, colour, IP and number on screen tinted, each with a bold label at its first cell. Open `hint-narrowed.png`: only the labels starting with the typed character remain (or, if that character was a whole label, the mode closed — say which the run showed).

- [ ] **Step 7: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `node --test ./bench/agent-session/session-api.test.mjs` → PASS.
- `npm run bench:selection` → PASS. `npm run bench:feel` → `PASS feel gate: zero pixel diff` (no chord in the gate).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.

CHANGELOG:

```markdown
- renderer-dom/react: Ctrl+Shift+Space (WezTerm's QuickSelect chord, `wezterm-gui/src/commands.rs`) labels every match of the package's rule set on the visible logical lines — WezTerm's `quickselect.rs` patterns minus IPFS, with Kitty's `path:line` (`kittens/hints/marks.go` `default_linenum_regex`) taking precedence over the bare path — with prefix-free labels from WezTerm's `compute_labels_for_alphabet`, assigned to the bottom-most match first and shared by identical texts. Typing a label emits `onHint({ ruleId, text, path?, line? })` and closes the mode; a character narrows the set, Backspace un-types, Escape or any other key cancels. While the mode is active no key reaches the pty. The chord costs one key: Ctrl+Shift+Space used to encode `\x00` like Ctrl+Space (`encodeKey`'s control branch ignores Shift), and the shifted form no longer reaches the child. Plain Ctrl+Space, the emacs set-mark readline binds, is unaffected and pinned by `encode-key.test.ts`. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-hint/`.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts packages/terminal/bench packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: hint mode — the chord, WezTerm's rules and labels, Kitty's path:line, onHint

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Secret redaction — host patterns, masked in the snapshot text the copy path and the block reader see, painted as masked highlights

**Files:**
- Modify: `packages/terminal/ts/core/src/{types.ts,index-browser.ts}` (`SecretPattern`, `HostCapabilities.secretPatterns?`)
- Create: `packages/terminal/ts/renderer-dom/src/{redaction.ts,redaction.test.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{dom-block-renderer.ts,dom-block-renderer.test.ts,styles.css,index.ts}`
- Modify: `packages/terminal/ts/react/src/{TerminalSurface.tsx,TerminalSurface.test.tsx}`
- Modify: `packages/terminal/bench/agent-session/{main.ts,affordance-gate.mjs,session-api.test.mjs}`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `logicalLineAt`/`LinkRange`/`LogicalLineView` and `rangeBoxes`/`paintBoxes`/`layer(name)` (Task 6), `TextRows` (Tasks 1/6), `selectedText` (`selection-text.ts`), `snapshotTextRows`/`textRows()` (Task 6), `renderBlockActions`'s `BlockTextSource` (`block-actions.ts:10`), `pointAt` (`dom-block-renderer.ts`).
- Produces: the "Redaction" shapes above. Task 9 passes Operator's pattern list and routes the daemon's own reader through the same Go patterns.

Masking happens where the text is *read*, not only where it is painted: `DomBlockRenderer.textRows()` returns masked rows once patterns are set, so the copy path (`selectedText`), word selection, the linkifier, hint mode and the block-output source all see `****` instead of the token. The paint is a highlight box over the masked cells, so the row DOM is untouched and the row pool is unaffected. Default off: with no patterns nothing is compiled, nothing is masked, nothing is painted. A click on a masked run reveals that one match until the next feed (Warp reveals on hover/click, `crates/warp_terminal/src/model/secrets.rs`); the mask character is `*`, Warp's (`grid_handler.rs:1134`).

- [ ] **Step 1: Write the failing tests**

`redaction.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { compileSecretPatterns, maskedTextRows, redactionMatches, REDACTION_MASK, secretRanges } from "./redaction";
import { logicalLineAt } from "./logical-lines";
import { selectedText, type TextRows } from "./selection-text";
import { ROW_END } from "./selection-model";

const patterns = compileSecretPatterns([
	{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b" },
	{ source: "bearer\\s+[A-Za-z0-9._-]{16,}", flags: "i" },
]);

function rowsOf(...texts: string[]): TextRows {
	return {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => texts.length,
		rowText: (_id, row) => texts[row] ?? "",
		rowSpans: () => [],
		rowWrapped: () => false,
	};
}

describe("compileSecretPatterns", () => {
	it("adds the global flag, keeps the caller's own and drops a pattern that does not compile", () => {
		const compiled = compileSecretPatterns([{ source: "a" }, { source: "b", flags: "i" }, { source: "(" }]);
		expect(compiled.map((regex) => [regex.source, regex.flags])).toEqual([["a", "g"], ["b", "gi"]]);
	});
});

describe("secretRanges", () => {
	it("covers each match, keeps a leading capture group visible and merges overlaps", () => {
		expect(secretRanges("use ghp_ABCDEFGHIJKLMNOPQRSTU now", patterns)).toEqual([{ start: 4, end: 29 }]);
		const bearer = compileSecretPatterns([{ source: "(Bearer )[A-Za-z0-9._-]{16,}" }]);
		expect(secretRanges("h: Bearer abcdefghijklmnopqrst", bearer)).toEqual([{ start: 10, end: 30 }]);
		const overlapping = compileSecretPatterns([{ source: "abcdef" }, { source: "cdefgh" }]);
		expect(secretRanges("xxabcdefghxx", overlapping)).toEqual([{ start: 2, end: 10 }]);
	});
	it("finds nothing in clean text and with no patterns", () => {
		expect(secretRanges("nothing here", patterns)).toEqual([]);
		expect(secretRanges("ghp_ABCDEFGHIJKLMNOPQRSTU", [])).toEqual([]);
	});
});

describe("maskedTextRows", () => {
	it("replaces every secret cell with the mask, cell for cell", () => {
		const masked = maskedTextRows(rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now"), patterns, new Set());
		expect(masked.rowText("b", 0)).toBe(`use ${REDACTION_MASK.repeat(25)} now`);
		expect(masked.rowText("b", 0)).toHaveLength(33);
	});
	it("copies masked, so the token never reaches the clipboard", () => {
		const masked = maskedTextRows(rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now"), patterns, new Set());
		const text = selectedText({ start: { blockId: "b", row: 0, cell: 0 }, end: { blockId: "b", row: 0, cell: ROW_END } }, masked);
		expect(text).toBe(`use ${REDACTION_MASK.repeat(25)} now`);
		expect(text).not.toContain("ghp_");
	});
	it("masks a secret split across a soft wrap, on both rows", () => {
		const wrapped: TextRows = { ...rowsOf("head ghp_ABCDEFGHIJ", "KLMNOPQRSTU tail"), rowWrapped: (_id, row) => row === 0 };
		const masked = maskedTextRows(wrapped, patterns, new Set());
		expect(masked.rowText("b", 0)).toBe(`head ${REDACTION_MASK.repeat(14)}`);
		expect(masked.rowText("b", 1)).toBe(`${REDACTION_MASK.repeat(11)} tail`);
	});
	it("leaves a revealed match alone and passes every other member through", () => {
		const rows = rowsOf("use ghp_ABCDEFGHIJKLMNOPQRSTU now");
		const line = logicalLineAt(rows, "b", 0)!;
		const key = redactionMatches(line, patterns)[0]!.key;
		const masked = maskedTextRows(rows, patterns, new Set([key]));
		expect(masked.rowText("b", 0)).toBe("use ghp_ABCDEFGHIJKLMNOPQRSTU now");
		expect(masked.blockIds).toEqual(["b"]);
		expect(masked.rowWrapped("b", 0)).toBe(false);
	});
});

describe("redactionMatches", () => {
	it("returns one stable key and range per secret on the line", () => {
		const line = logicalLineAt(rowsOf("a ghp_ABCDEFGHIJKLMNOPQRSTU b"), "b", 0)!;
		const matches = redactionMatches(line, patterns);
		expect(matches).toHaveLength(1);
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 2, endRow: 0, endCell: 27 });
		expect(redactionMatches(line, patterns)[0]!.key).toBe(matches[0]!.key);
	});
});
```

Add to `dom-block-renderer.test.ts`:

```ts
	it("masks a secret in the copy text and paints it, only once the host supplies patterns", async () => {
		const { host, renderer } = mountWith("token ghp_ABCDEFGHIJKLMNOPQRSTU end\r\n");
		await flushRepaint();
		renderer.selectionBegin({ blockId: "0:0", row: 0, column: 0, side: "left" }, "line");
		expect(renderer.selectedText()).toContain("ghp_ABCDEFGHIJKLMNOPQRSTU");
		expect(host.querySelectorAll(".terminal-redaction")).toHaveLength(0);
		renderer.setSecretPatterns([{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b" }]);
		await flushRepaint();
		expect(renderer.selectedText()).not.toContain("ghp_");
		expect(renderer.selectedText()).toContain("*".repeat(25));
		expect(host.querySelectorAll(".terminal-redaction")).toHaveLength(1);
		expect(host.textContent).toContain("ghp_ABCDEFGHIJKLMNOPQRSTU");
	});
```

(the row text itself is not rewritten — the mask is a paint over it and a transform on what is read; the last assertion pins that, and is why the CHANGELOG says a screen reader still sees the token.)

Add to `TerminalSurface.test.tsx`:

```ts
	it("passes the host's secret patterns to the renderer and nothing when there are none", () => {
		const setSecretPatterns = vi.spyOn(DomBlockRenderer.prototype, "setSecretPatterns");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, secretPatterns: [{ source: "x" }] };
		render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} host={host} onSend={() => undefined} onSendRaw={() => undefined} />);
		expect(setSecretPatterns).toHaveBeenLastCalledWith([{ source: "x" }]);
		setSecretPatterns.mockRestore();
	});
```

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal/ts/renderer-dom && npx vitest run src/redaction.test.ts` → FAIL, module not found.

- [ ] **Step 2: Implement `redaction.ts`**

`ts/core/src/types.ts`:

```ts
export type SecretPattern = Readonly<{ source: string; flags?: string }>;
```

and `secretPatterns?: readonly SecretPattern[];` on `HostCapabilities` after `openPath?`. `index-browser.ts`: `export type { SecretPattern } from "./types.js";` (added to the existing type export list).

`packages/terminal/ts/renderer-dom/src/redaction.ts`:

```ts
import type { SecretPattern } from "@operator/terminal-core";
import { cellAtOffset } from "./clusters.js";
import { logicalLineAt, type LinkRange, type LogicalLineView } from "./logical-lines.js";
import type { TextRows } from "./selection-text.js";

// warp/crates/warp_terminal/src/model/grid/grid_handler.rs:1134 (the placeholder char)
export const REDACTION_MASK = "*";

export type SecretRange = Readonly<{ start: number; end: number }>;
export type RedactionMatch = Readonly<{ key: string; range: LinkRange }>;

export function compileSecretPatterns(patterns: readonly SecretPattern[]): RegExp[] {
	const out: RegExp[] = [];
	for (const pattern of patterns) {
		const flags = pattern.flags ?? "";
		try {
			out.push(new RegExp(pattern.source, flags.includes("g") ? flags : `${flags}g`));
		} catch {
			continue;
		}
	}
	return out;
}

export function secretRanges(text: string, regexes: readonly RegExp[]): SecretRange[] {
	const hits: SecretRange[] = [];
	for (const regex of regexes) {
		regex.lastIndex = 0;
		for (const match of text.matchAll(regex)) {
			const whole = match.index ?? 0;
			let start = whole;
			let end = whole + match[0].length;
			const first = match[1];
			if (first !== undefined && match[0].startsWith(first)) start += first.length;
			const last = match[match.length - 1];
			if (match.length > 2 && last !== undefined && last !== "" && match[0].endsWith(last)) end -= last.length;
			if (end > start) hits.push({ start, end });
		}
	}
	hits.sort((a, b) => a.start - b.start);
	const merged: SecretRange[] = [];
	for (const hit of hits) {
		const previous = merged[merged.length - 1];
		if (previous && hit.start <= previous.end) {
			merged[merged.length - 1] = { start: previous.start, end: Math.max(previous.end, hit.end) };
			continue;
		}
		merged.push(hit);
	}
	return merged;
}

export function redactionMatches(line: LogicalLineView, regexes: readonly RegExp[]): RedactionMatch[] {
	return secretRanges(line.text, regexes).map((range) => ({
		key: `${line.blockId}:${line.firstRow}:${range.start}:${range.end}`,
		range: line.rangeOf(range.start, range.end),
	}));
}

export function maskedTextRows(rows: TextRows, regexes: readonly RegExp[], revealed: ReadonlySet<string>): TextRows {
	if (regexes.length === 0) return rows;
	const cache = new Map<string, string>();
	const maskedRow = (blockId: string, row: number): string => {
		const key = `${blockId}:${row}`;
		const hit = cache.get(key);
		if (hit !== undefined) return hit;
		const text = rows.rowText(blockId, row);
		const line = logicalLineAt(rows, blockId, row);
		if (!line) {
			cache.set(key, text);
			return text;
		}
		const offset = line.rowOffsets[row - line.firstRow] ?? 0;
		let out = text;
		for (const range of secretRanges(line.text, regexes)) {
			if (revealed.has(`${line.blockId}:${line.firstRow}:${range.start}:${range.end}`)) continue;
			const from = Math.max(range.start - offset, 0);
			const to = Math.min(range.end - offset, text.length);
			if (to <= from) continue;
			out = out.slice(0, from) + REDACTION_MASK.repeat(to - from) + out.slice(to);
		}
		cache.set(key, out);
		return out;
	};
	return { ...rows, rowText: maskedRow };
}

export function maskedCellRange(text: string, spans: ArrayLike<number>, from: number, to: number): { startCell: number; endCell: number } {
	return { startCell: cellAtOffset(text, spans, from), endCell: cellAtOffset(text, spans, to) };
}
```

(`maskedTextRows` keeps every other member by spreading `rows`, which is what "passes every other member through" pins. It masks per *row* from the logical line's own ranges, so a secret split by a soft wrap is masked on both rows — the third test. `maskedCellRange` is exported for a host that needs cells rather than offsets; the renderer uses `rangeOf`.)

Run: `npx vitest run src/redaction.test.ts` → PASS. The `secretRanges` leading/trailing-group rule mirrors `backend/internal/redact/redact.go`'s `Text` (a leading group at the match start is kept, a trailing group at the match end is kept), which is what makes Operator's Go patterns behave the same on both sides in Task 9.

- [ ] **Step 3: Wire the renderer and the surface**

`styles.css`, after `.terminal-hint-label`:

```css
/* A masked secret is painted over its cells rather than rewritten into the row,
   so the model keeps the bytes and only what is READ is masked (Warp
   crates/warp_terminal/src/model/secrets.rs, RespectObfuscatedSecrets). */
.terminal-redaction {
	background: var(--terminal-foreground);
	opacity: 0.85;
}
```

`dom-block-renderer.ts`:
- imports: `compileSecretPatterns, maskedTextRows, redactionMatches` from `./redaction.js`; `rangeContains` added to the existing `./logical-lines.js` import; `type SecretPattern` from `@operator/terminal-core`.
- fields `private secretRegexes: RegExp[] = [];` and `private revealedSecrets = new Set<string>();`
- `textRows()` (Task 6) becomes:
  ```ts
  	private textRows(): TextRows {
  		const core = this.core!;
  		const rows = snapshotTextRows(core.snapshot(), this.currentFilter, this.decoder, (id) => core.linkUri(id));
  		return maskedTextRows(rows, this.secretRegexes, this.revealedSecrets);
  	}
  ```
- public API:
  ```ts
  	setSecretPatterns(patterns: readonly SecretPattern[]): void {
  		this.secretRegexes = compileSecretPatterns(patterns);
  		this.revealedSecrets.clear();
  		this.scheduleRepaint();
  	}

  	revealSecretAt(x: number, y: number): void {
  		if (this.secretRegexes.length === 0) return;
  		const point = this.pointAt(x, y);
  		if (!point) return;
  		const line = logicalLineAt(this.textRows(), point.blockId, point.row);
  		if (!line) return;
  		for (const match of redactionMatches(line, this.secretRegexes)) {
  			if (!rangeContains(match.range, point.row, point.column)) continue;
  			this.revealedSecrets.add(match.key);
  			this.scheduleRepaint();
  			return;
  		}
  	}
  ```
- private, called from `repaint` beside `this.paintHints();` on both exit paths:
  ```ts
  	private paintRedactions(): void {
  		const layer = this.layer("redactions");
  		const container = this.container;
  		if (!layer || !container) return;
  		if (this.secretRegexes.length === 0) {
  			paintBoxes(layer, "terminal-redaction", []);
  			return;
  		}
  		const rows = this.textRows();
  		const seen = new Set<string>();
  		const boxes = [];
  		const rendered = this.renderedRows();
  		const { cellWidth } = this.cellMetrics();
  		for (const { box } of rendered) {
  			const line = logicalLineAt(rows, box.blockId, box.row);
  			if (!line) continue;
  			const key = `${line.blockId}:${line.firstRow}`;
  			if (seen.has(key)) continue;
  			seen.add(key);
  			for (const match of redactionMatches(line, this.secretRegexes)) {
  				if (this.revealedSecrets.has(match.key)) continue;
  				boxes.push(...rangeBoxes(match.range, rendered, cellWidth, container));
  			}
  		}
  		paintBoxes(layer, "terminal-redaction", boxes);
  	}
  ```
- `dispose()`: `this.secretRegexes = []; this.revealedSecrets.clear();`. Also clear `revealedSecrets` in `repaint` when `snapshot.generation` differs from the generation the reveals were recorded at — keep a `private revealedAt = -1;` field, set it in `revealSecretAt` to the current generation, and in `repaint` do `if (this.revealedAt !== snapshot.generation) { this.revealedSecrets.clear(); this.revealedAt = snapshot.generation; }` before the paints (a reveal lasts until the next feed, as the CHANGELOG says).

`index.ts`: `export { REDACTION_MASK, compileSecretPatterns, secretRanges } from "./redaction.js";`.

`TerminalSurface.tsx`: an effect beside the providers one —

```tsx
	const secretPatterns = host?.secretPatterns;
	useLayoutEffect(() => {
		rendererRef.current?.setSecretPatterns(secretPatterns ?? []);
	}, [secretPatterns]);
```

and in the mouse effect's `onMouseDown`, right after the link-modifier branch: `if (button === 0 && !event.altKey) renderer()?.revealSecretAt(event.clientX, event.clientY);` (a plain click; the selection branch below still runs, so a click both reveals and clears the selection as it did).

Run: `cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.

- [ ] **Step 4: The harness action and the screenshot**

`bench/agent-session/main.ts`: `setSecretPatterns(patterns: { source: string; flags?: string }[]): void;` on the `AgentSession` type and `setSecretPatterns: (patterns) => domRenderer.setSecretPatterns(patterns),` on the object; `session-api.test.mjs`'s list gains `"setSecretPatterns"`.

`affordance-gate.mjs` — add to `actions`:

```js
	async redact(page, shoot) {
		await shoot("redact-off");
		await page.evaluate(() => window.__agentSession.setSecretPatterns([
			{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b" },
			{ source: "\\bAKIA[0-9A-Z]{16}\\b" },
		]));
		await page.waitForTimeout(150);
		await shoot("redact-on");
		const painted = await page.evaluate(() => document.querySelectorAll(".terminal-redaction").length);
		await page.evaluate(() => window.__agentSession.setSecretPatterns([]));
		return [["redact-boxes", painted, null]];
	},
```

Run `npm run bench:affordances -- --action redact` → two `side-by-side …` lines and `["redact-boxes", 2, null]`. Compare `redact-off.png` and `redact-on.png`: the `ghp_…` and `AKIA…` runs on line 4 are covered; everything else is identical.

- [ ] **Step 5: Verify and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`:
- `npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done` → PASS.
- `node --test ./bench/agent-session/session-api.test.mjs` → PASS.
- `npm run bench:selection` → PASS (the copy path changed). `npm run bench:feel` → `PASS feel gate: zero pixel diff` (the gate passes no patterns).
- `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p .` → clean.

CHANGELOG:

```markdown
- renderer-dom/react: with `HostCapabilities.secretPatterns` set, every match on a visible logical line is painted as a masked highlight and masked cell-for-cell with `*` (Warp's placeholder, `crates/warp_terminal/src/model/grid/grid_handler.rs`) in every text the renderer *reads* — the copy path, word selection, the linkifier, hint mode and the block-output source — so a token cannot reach the clipboard or a ticket. A leading capture group at the match start stays visible ("Bearer [redacted]"), overlapping matches merge, and a secret split by a soft wrap is masked on both rows. A plain click reveals one match until the next feed. Default off: with no patterns nothing is compiled, masked or painted. The row DOM keeps the original text (the mask is a paint plus a read transform), so a screen reader and the accessibility tree still see it — recorded in `TERMINAL.md` §5. Side-by-side: `bench/agent-session/baselines/act-probe/affordance-redact/`.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add packages/terminal/ts packages/terminal/bench packages/terminal/CHANGELOG.md && git commit -m "renderer-dom: secret redaction from host patterns — masked in copy, block text and paint

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Operator host wiring — `resolvePath`, `openPath`, `secretPatterns`, `onHint`, `onBlockFinished`, and the daemon's own reader

**Files:**
- Modify: `frontend/src-tauri/src/native.rs` (`resolve_path`, `open_path`), `frontend/src-tauri/src/lib.rs` (the handler list), `frontend/src-tauri/capabilities/default.json`
- Modify: `frontend/src/shared/operator-bridge.ts`, `frontend/src/renderer/lib/{tauri-bridge.ts,bridge.ts,tauri-bridge.test.ts}`
- Create: `frontend/src/renderer/lib/{terminal-secret-redaction.ts,terminal-secret-redaction.test.ts,redaction-patterns.ts,redaction-patterns.test.ts}`
- Modify: `frontend/src/renderer/stores/ui-store.ts`, `frontend/src/renderer/components/settings/GeneralSettingsSection.tsx`, `frontend/src/renderer/i18n/en.json`
- Modify: `frontend/src/renderer/components/{BlockTerminal.tsx,BlockTerminal.test.tsx,TerminalPane.tsx}`
- Create: `backend/internal/redact/{jspatterns.go,jspatterns_test.go}`, `backend/internal/httpd/controllers/{redaction.go,redaction_test.go}`
- Modify: `backend/internal/httpd/api.go`, `backend/internal/httpd/apispec/specgen/build.go`, regenerate `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts`
- Modify: `backend/internal/session_manager/{slash_output.go,slash_output_test.go,agent_switching.go,agent_switching_test.go}`
- Modify: `packages/terminal/CHANGELOG.md`

**Interfaces:**
- Consumes: `HostCapabilities.{resolvePath,openPath,secretPatterns}` (Tasks 6, 8), `TerminalSurface` props `onHint` (Task 7) and `onBlockFinished` (Task 4), `operatorBridge.app.openExternal` + `openLinkInSystemBrowser`/`isWebLink` (`frontend/src/renderer/lib/external-link-policy.ts`), the Tauri command pattern (`native.rs:150` `open_external`, `is_allowed_app_external_url` at `:39`), `redact.Text` and its `patterns` (`backend/internal/redact/redact.go:32`), `WorkspaceSession.workspacePath` (`frontend/src/renderer/types/workspace.ts:137`), `operatorBridge.notifications.show`, the specgen route table (`build.go:445,1082`) and `api.go:93,132,170`.
- Produces: Operator's implementations of the three seams; `onHint` → open in the editor / copy; `onBlockFinished` → a desktop notification for a long command that finished out of sight; `GET /api/v1/redaction/patterns`; the two daemon readers that re-transmit terminal text routed through `redact.Text`.

`packages/terminal` gains nothing in this task — every line is Operator's own policy.

- [ ] **Step 1: The Tauri commands, failing test first**

Add to `frontend/src-tauri/src/native.rs`, beside `is_allowed_app_external_url`:

```rust
pub fn resolved_link_path(base: Option<&str>, path: &str) -> Option<PathBuf> {
    let trimmed = path.trim();
    if trimmed.is_empty() || trimmed.contains('\0') {
        return None;
    }
    let expanded = if let Some(rest) = trimmed.strip_prefix("~/") {
        std::env::var_os("HOME").map(PathBuf::from)?.join(rest)
    } else {
        PathBuf::from(trimmed)
    };
    let candidate = if expanded.is_absolute() {
        expanded
    } else {
        PathBuf::from(base?).join(expanded)
    };
    let resolved = candidate.canonicalize().ok()?;
    resolved.exists().then_some(resolved)
}
```

and to `frontend/src-tauri/src/native_contract_tests.rs`:

```rust
#[test]
fn a_link_path_resolves_only_when_it_exists_and_needs_a_base_when_relative() {
    use crate::native::resolved_link_path;
    let dir = std::env::temp_dir().join(format!("operator-link-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temp dir");
    let file = dir.join("exists.ts");
    std::fs::write(&file, b"x").expect("write");
    let base = dir.to_string_lossy().to_string();

    assert_eq!(
        resolved_link_path(Some(&base), "exists.ts"),
        Some(file.canonicalize().expect("canonicalize"))
    );
    assert_eq!(resolved_link_path(Some(&base), "missing.ts"), None);
    assert_eq!(resolved_link_path(None, "exists.ts"), None);
    assert_eq!(
        resolved_link_path(None, file.to_str().expect("utf-8")),
        Some(file.canonicalize().expect("canonicalize"))
    );
    assert_eq!(resolved_link_path(Some(&base), "  "), None);
    std::fs::remove_dir_all(&dir).ok();
}
```

Run: `cd /Users/omaraly/development/AI/Operator/frontend/src-tauri && cargo test resolved_link_path` → FAIL (no such function), then PASS once the function above is in place.

Then the two commands (after `open_external`):

```rust
#[tauri::command]
pub async fn resolve_path(base: Option<String>, path: String) -> Result<Option<String>, String> {
    Ok(tauri::async_runtime::spawn_blocking(move || {
        resolved_link_path(base.as_deref(), &path).map(|resolved| resolved.to_string_lossy().to_string())
    })
    .await
    .map_err(|error| error.to_string())?)
}

#[tauri::command]
pub async fn open_path(app: AppHandle, path: String) -> Result<(), String> {
    let resolved = resolved_link_path(None, &path).ok_or_else(|| "Unknown path".to_string())?;
    app.opener()
        .open_path(resolved.to_string_lossy().to_string(), None::<&str>)
        .map_err(|error| error.to_string())
}
```

`lib.rs`: add `native::resolve_path,` and `native::open_path,` to the non-audit `generate_handler!` list (the one at `:1168`, after `native::open_external`). `capabilities/default.json`: add `"allow-resolve-path"` and `"allow-open-path"` after `"allow-open-external"`.

Run: `cd /Users/omaraly/development/AI/Operator/frontend/src-tauri && cargo fmt && cargo test && cargo check` → PASS. `open_path` hands the file to the OS opener, which is the user's editor for a source file; the line number is not passed because `tauri-plugin-opener` has no argument for it — `openPath(path, line, column)` accepts them and Operator ignores them for now, recorded in the CHANGELOG and in Task 10's note.

- [ ] **Step 2: The bridge, failing test first**

`frontend/src/shared/operator-bridge.ts`, in the `app` block after `openExternal`:

```ts
		resolvePath: (base: string | null, path: string) => Promise<string | null>;
		openPath: (path: string) => Promise<void>;
```

Add to `frontend/src/renderer/lib/tauri-bridge.test.ts` (beside the `openExternal` case at `:324`):

```ts
	it("passes a link path and its base to the native resolver and opens a resolved path", async () => {
		const tauri = createTauriBridge();
		invokeMock.mockResolvedValueOnce("/abs/src/a.ts");
		await expect(tauri.app.resolvePath("/work", "src/a.ts")).resolves.toBe("/abs/src/a.ts");
		expect(invokeMock).toHaveBeenLastCalledWith("resolve_path", { base: "/work", path: "src/a.ts" });
		invokeMock.mockResolvedValueOnce(null);
		await expect(tauri.app.resolvePath(null, "src/a.ts")).resolves.toBeNull();
		invokeMock.mockResolvedValueOnce(undefined);
		await expect(tauri.app.openPath("/abs/src/a.ts")).resolves.toBeUndefined();
		expect(invokeMock).toHaveBeenLastCalledWith("open_path", { path: "/abs/src/a.ts" });
	});
```

(use the file's own bridge factory and `invoke` mock names — read the top of `tauri-bridge.test.ts` and match them.)

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/lib/tauri-bridge.test.ts -t "link path"` → FAIL.

`tauri-bridge.ts`, after `openExternal`:

```ts
			resolvePath: async (base: string | null, path: string) =>
				(await invoke("resolve_path", { base, path })) as string | null,
			openPath: async (path: string) => {
				await invoke("open_path", { path });
			},
```

`bridge.ts` (the preview fallback), after its `openExternal`: `resolvePath: async () => null, openPath: async () => undefined,`.

Run the test → PASS.

- [ ] **Step 3: The daemon's pattern route, failing test first**

`backend/internal/redact/jspatterns_test.go`:

```go
package redact

import "testing"

func TestJSPatternsAreEcmaCompatibleAndCoverTheBuiltins(t *testing.T) {
	patterns := JSPatterns()
	if len(patterns) != len(builtinPatterns) {
		t.Fatalf("got %d patterns, want %d", len(patterns), len(builtinPatterns))
	}
	for _, pattern := range patterns {
		if pattern.Source == "" {
			t.Fatalf("empty source in %+v", pattern)
		}
		if got := pattern.Source; containsGoOnlySyntax(got) {
			t.Fatalf("pattern %q carries Go-only syntax that JavaScript cannot compile", got)
		}
	}
	var sawCaseInsensitive bool
	for _, pattern := range patterns {
		if pattern.Flags == "i" {
			sawCaseInsensitive = true
		}
	}
	if !sawCaseInsensitive {
		t.Fatal("expected at least one case-insensitive pattern (the (?i) ones)")
	}
}
```

with the helper in the test file:

```go
func containsGoOnlySyntax(source string) bool {
	for _, token := range []string{"(?i)", "(?s)", "(?m)", "(?U)", "(?P<"} {
		if len(source) >= len(token) && indexOf(source, token) >= 0 {
			return true
		}
	}
	return false
}

func indexOf(haystack, needle string) int {
	for index := 0; index+len(needle) <= len(haystack); index++ {
		if haystack[index:index+len(needle)] == needle {
			return index
		}
	}
	return -1
}
```

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/redact/ -run TestJSPatterns` → FAIL (no `JSPatterns`, no `builtinPatterns`).

`backend/internal/redact/redact.go`: rename the `patterns` var to `builtinPatterns` and keep a parallel slice of the sources and flags in the same order (the only way to hand a Go regex to JavaScript is to carry its source deliberately):

```go
type jsPattern struct {
	Source string
	Flags  string
}

var builtinJSPatterns = []jsPattern{
	{Source: `\bAKIA[0-9A-Z]{16}\b`, Flags: "i"},
	{Source: `\bgh[pousr]_[A-Za-z0-9]{20,}\b`, Flags: ""},
	{Source: `\bsk-[A-Za-z0-9_\-]{20,}\b`, Flags: ""},
	{Source: `(bearer\s+)[A-Za-z0-9._\-]{16,}`, Flags: "i"},
	{Source: `((?:api[_\-]?key|secret|token|password)\s*[:=]\s*)[^\s"']{8,}`, Flags: "i"},
	{Source: `([a-z][a-z0-9+.\-]*://[^\s:/@]+:)[^\s@]+(@)`, Flags: ""},
}
```

`backend/internal/redact/jspatterns.go`:

```go
package redact

// Pattern is one secret shape in the form a JavaScript RegExp takes: Go's
// (?i) inline flag has no ECMAScript equivalent, so it travels as a flag.
type Pattern struct {
	Source string `json:"source"`
	Flags  string `json:"flags"`
}

// JSPatterns returns the built-in shapes for a client that does its own
// masking. User patterns from redact-patterns.txt are deliberately not
// included: they are Go syntax the user wrote for this daemon, and a client
// that cannot compile one would silently mask less than the daemon does.
func JSPatterns() []Pattern {
	out := make([]Pattern, 0, len(builtinJSPatterns))
	for _, pattern := range builtinJSPatterns {
		out = append(out, Pattern{Source: pattern.Source, Flags: pattern.Flags})
	}
	return out
}
```

Add a test that the two lists cannot drift, in `jspatterns_test.go`:

```go
func TestEveryBuiltinPatternHasAJSForm(t *testing.T) {
	if len(builtinPatterns) != len(builtinJSPatterns) {
		t.Fatalf("%d Go patterns against %d JS forms: add the JS form beside the Go one", len(builtinPatterns), len(builtinJSPatterns))
	}
}
```

`backend/internal/httpd/controllers/redaction.go`:

```go
package controllers

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/redact"
)

type RedactionController struct{}

type RedactionPattern struct {
	Source string `json:"source"`
	Flags  string `json:"flags"`
}

type RedactionPatternsResponse struct {
	Patterns []RedactionPattern `json:"patterns"`
}

func (c *RedactionController) Register(r chi.Router) {
	r.Get("/redaction/patterns", c.Patterns)
}

func (c *RedactionController) Patterns(w http.ResponseWriter, _ *http.Request) {
	patterns := redact.JSPatterns()
	out := make([]RedactionPattern, 0, len(patterns))
	for _, pattern := range patterns {
		out = append(out, RedactionPattern{Source: pattern.Source, Flags: pattern.Flags})
	}
	envelope.WriteJSON(w, http.StatusOK, RedactionPatternsResponse{Patterns: out})
}
```

`backend/internal/httpd/controllers/redaction_test.go`:

```go
package controllers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRedactionPatternsReturnsEveryBuiltinShape(t *testing.T) {
	recorder := httptest.NewRecorder()
	(&RedactionController{}).Patterns(recorder, httptest.NewRequest(http.MethodGet, "/api/v1/redaction/patterns", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status %d", recorder.Code)
	}
	var body RedactionPatternsResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body.Patterns) == 0 {
		t.Fatal("no patterns")
	}
	for _, pattern := range body.Patterns {
		if pattern.Source == "" {
			t.Fatalf("empty source: %+v", body.Patterns)
		}
	}
}
```

`api.go`: field `redaction *controllers.RedactionController`, construction `redaction: &controllers.RedactionController{},`, and `a.redaction.Register(r)` beside `a.desktop.Register(r)`. `specgen/build.go`: a `redactionOperations()` next to `desktopOperations()`:

```go
func redactionOperations() []operation {
	return []operation{
		{
			method: http.MethodGet, path: "/api/v1/redaction/patterns", id: "getRedactionPatterns", tag: "redaction",
			summary: "List the secret shapes a client should mask locally",
			resps: []respUnit{
				{http.StatusOK, controllers.RedactionPatternsResponse{}},
			},
		},
	}
}
```

appended in `operations()` (`ops = append(ops, redactionOperations()...)`), plus `"ControllersRedactionPatternsResponse": "RedactionPatternsResponse",` and `"ControllersRedactionPattern": "RedactionPattern",` in the name map beside `"ControllersDesktopResponse"`.

Run: `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/redact/... ./internal/httpd/... ` → PASS (the route-parity test is what fails if the specgen entry is missing). Then `cd /Users/omaraly/development/AI/Operator/backend/internal/httpd/apispec && go generate ./...` and `cd /Users/omaraly/development/AI/Operator/frontend && npm run api:ts`.

- [ ] **Step 4: The daemon's own readers**

Two call sites re-transmit terminal text without passing through `redact.Text`: `SlashOutput` (`slash_output.go:45`, returned to the UI and the mobile client) and the pre-stop terminal tail in `agent_switching.go:305-307`, which lands in a handoff record. Both get `redact.Text(...).Text`.

`slash_output_test.go` — add:

`slash_output_test.go` uses `newSlashOutputTestManager(t, panes…)` — the helper `TestSlashOutputReturnsOnceTwoReadsAgree` (`:87`) calls, which feeds a fake runtime the pane strings it is given. Add beside it:

```go
func TestSlashOutputRedactsASecretInThePane(t *testing.T) {
	const pane = "/context\nContext Usage token ghp_ABCDEFGHIJKLMNOPQRSTU done\n"
	m, _, _ := newSlashOutputTestManager(t, pane, pane)

	got, err := m.SlashOutput(context.Background(), "s1", "/context")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "ghp_") {
		t.Fatalf("slash output leaked a token: %q", got)
	}
	if !strings.Contains(got, "[redacted]") {
		t.Fatalf("slash output did not mark the redaction: %q", got)
	}
}
```

(If `newSlashOutputTestManager`'s session id or the `/context` echo shape differs, copy them from `:87` verbatim — the two assertions are the test.)

`agent_switching_test.go`: `TestBuildTargetContinuationMessageIncludesDeterministicContextAndFallbackTail` (`:603`) is the test that already exercises the terminal tail. Add a sibling that puts `token ghp_ABCDEFGHIJKLMNOPQRSTU done` in the pane its fake runtime returns and asserts the built message carries `[redacted]` and no `ghp_`.

Run `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/session_manager/ -run 'SlashOutputRedacts|FallbackTail'` → FAIL, then apply `redact.Text(pane).Text` at `slash_output.go:45`'s result and at `agent_switching.go:306`'s `normalizeTerminalTail(output)` argument → PASS.

- [ ] **Step 5: The renderer's host wiring, failing test first**

`frontend/src/renderer/lib/redaction-patterns.ts`:

```ts
import type { SecretPattern } from "@operator/terminal-react";
import { apiClient, apiErrorMessage } from "./api-client";

export const redactionPatternsQueryKey = ["redaction", "patterns"] as const;

export async function fetchRedactionPatterns(): Promise<SecretPattern[]> {
	const { data, error } = await apiClient.GET("/api/v1/redaction/patterns", {});
	if (error) throw new Error(apiErrorMessage(error));
	return (data?.patterns ?? []).map((pattern) => ({ source: pattern.source, flags: pattern.flags }));
}
```

`redaction-patterns.test.ts`: one test that a stubbed response maps to `{ source, flags }` pairs and one that an error throws — follow `frontend/src/renderer/lib/notifications.test.ts`'s stubbing of `apiClient`.

`frontend/src/renderer/lib/terminal-secret-redaction.ts`: the persisted toggle, exactly the shape of `terminal-font-size.ts`:

```ts
export const terminalSecretRedactionStorageKey = "opr.terminal.secretRedaction";
export const defaultTerminalSecretRedaction = false;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

export function readStoredTerminalSecretRedaction(): boolean {
	try {
		return getLocalStorage()?.getItem(terminalSecretRedactionStorageKey) === "1";
	} catch {
		return defaultTerminalSecretRedaction;
	}
}
```

`terminal-secret-redaction.test.ts`: reads `"1"` as true, anything else and a throwing storage as false (mirror `terminal-font-size.test.ts`).

`ui-store.ts`: `terminalSecretRedaction: boolean` in the state, `initialTerminalSecretRedaction` from `readStoredTerminalSecretRedaction()`, and

```ts
	setTerminalSecretRedaction: (terminalSecretRedaction) => {
		if (get().terminalSecretRedaction === terminalSecretRedaction) return;
		getLocalStorage()?.setItem(terminalSecretRedactionStorageKey, terminalSecretRedaction ? "1" : "0");
		set({ terminalSecretRedaction });
	},
```

`GeneralSettingsSection.tsx`: a `SettingsRow` with the `Switch` primitive (`../ui/switch`, the pattern `TicketDefaultsSection.tsx:137` uses) bound to the store, labelled `t("settings.terminalSecretRedaction")`; `en.json` gains `"terminalSecretRedaction": "Mask secrets in the terminal"` beside `terminalFontSize`.

Add to `frontend/src/renderer/components/BlockTerminal.test.tsx`:

The file mocks `@operator/terminal-react` and records the props it was given on a hoisted `mockState` (`:17-40`, `:126-151`). Extend the mock's prop type and its recording with `onHint`, `onBlockFinished` and the three new `host` members (`mockState.onHint = props.onHint; mockState.onBlockFinished = props.onBlockFinished;`, and widen `mockState.host`'s type to `{ writeClipboard: …; openLink: …; resolvePath?: (path: string, cwd: string) => Promise<string | null>; openPath?: (path: string) => Promise<void>; secretPatterns?: readonly { source: string; flags?: string }[] }`), then add:

```ts
	it("gives the surface the path resolver, the editor opener, the host's patterns and the two callbacks", () => {
		renderTerminal({ workspacePath: "/work" });
		expect(typeof mockState.host?.resolvePath).toBe("function");
		expect(typeof mockState.host?.openPath).toBe("function");
		expect(mockState.host?.secretPatterns).toEqual([]);
		expect(typeof mockState.onHint).toBe("function");
		expect(typeof mockState.onBlockFinished).toBe("function");
	});
```

(`renderTerminal` is this file's own render helper at `:272`; give it the new `workspacePath` prop the way it already passes `fontSize` and `agentTui`.)

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer/components/BlockTerminal.test.tsx -t "path resolver"` → FAIL.

- [ ] **Step 6: Implement the renderer wiring**

`BlockTerminal.tsx`:
- props: `workspacePath?: string;` (documented as the cwd relative paths resolve against when a block carries none).
- the `host` memo gains:
  ```ts
  			resolvePath: async (path: string, cwd: string) =>
  				operatorBridge.app.resolvePath(cwd || workspacePath || null, path),
  			openPath: async (path: string) => {
  				await operatorBridge.app.openPath(path);
  			},
  			secretPatterns,
  ```
  with `workspacePath` and `secretPatterns` in its dependency list.
- `secretPatterns` comes from the toggle and the query:
  ```ts
  	const redactSecrets = useUiStore((state) => state.terminalSecretRedaction);
  	const { data: patterns } = useQuery({ queryKey: redactionPatternsQueryKey, queryFn: fetchRedactionPatterns, enabled: redactSecrets, staleTime: Infinity });
  	const secretPatterns = useMemo(() => (redactSecrets ? patterns ?? [] : []), [redactSecrets, patterns]);
  ```
- `surfaceProps` gains:
  ```ts
  		onHint: (hint) => {
  			if (hint.path !== undefined) {
  				void operatorBridge.app.openPath(hint.path);
  				return;
  			}
  			if (isWebLink(hint.text)) {
  				void openLinkInSystemBrowser(hint.text);
  				return;
  			}
  			void host.writeClipboard(hint.text);
  		},
  		onBlockFinished: ({ id, exitCode, durationMs, visible }) => {
  			if (visible || durationMs === null || durationMs < BLOCK_NOTIFY_AFTER_MS) return;
  			void operatorBridge.notifications.show({
  				id: `block-finished:${sessionId}:${id}`,
  				title: exitCode === 0 || exitCode === null ? t("terminal.blockFinished") : t("terminal.blockFailed"),
  				body: t("terminal.blockFinishedBody", { seconds: Math.round(durationMs / 1000) }),
  				type: "terminal",
  			});
  		},
  ```
  with `const BLOCK_NOTIFY_AFTER_MS = 10_000;` beside `DEFAULT_LIMITS` (Kitty's `notify_on_cmd_finish unfocused 10.0`, `kitty/kitty/options/definition.py`) and the three strings in `en.json` (`terminal.blockFinished` "Command finished", `terminal.blockFailed` "Command failed", `terminal.blockFinishedBody` "after {{seconds}}s").

`TerminalPane.tsx`: `workspacePath={session?.workspacePath}` on `<BlockTerminal … />`.

Run: `cd /Users/omaraly/development/AI/Operator/frontend && npx vitest run src/renderer && npx tsc --noEmit -p . && npm run lint` → PASS, clean.

- [ ] **Step 7: Verify in the real app**

`TERMINAL.md` §6 plus the real-app recipe in the memory `verify-renderer-in-browser-against-isolated-daemon`:
- `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`, restart the daemon and the app (`npm run tauri:dev` from the repo root, with the `CLAUDE*` env scrubbed).
- In a Claude Code pane: hover a `path:line` it printed → underline plus the hand; Cmd-click → the file opens in the editor. Hover a URL → Cmd-click opens the browser. Ctrl+Shift+Space → labels; type one over a path → the file opens. Turn "Mask secrets in the terminal" on in Settings, `echo ghp_$(python3 -c "print('A'*36)")` in a shell pane → the token is masked, a click reveals it, copy yields `****`. Run `sleep 12; echo done` in a shell pane, switch away before it finishes → one desktop notification.
- Report what each step showed. A step that does not work is a finding to report, not something to work around.

- [ ] **Step 8: Commit**

CHANGELOG (`packages/terminal/CHANGELOG.md` — one line, because the package's seams are what changed for a host; the rest is Operator's own and belongs in the app's own notes):

```markdown
- Operator (host side, no package change): `resolvePath` is a Tauri command (`resolve_path`) that canonicalises a candidate against the block's cwd or the session's workspace path and answers only for a file that exists; `openPath` hands the resolved file to the OS opener (`open_path`), which opens the user's editor — the line and column the package passes are accepted and not yet used, because `tauri-plugin-opener` takes no editor argument. `secretPatterns` comes from the daemon's own built-in shapes over `GET /api/v1/redaction/patterns` behind a Settings switch, default off, so the desktop masks exactly what the daemon redacts. `onHint` opens a path in the editor, a URL in the browser and copies anything else; `onBlockFinished` raises one desktop notification for a command that took at least 10 s and finished while its pane was out of sight (Kitty's `notify_on_cmd_finish unfocused 10.0`). `SlashOutput` and the agent-handoff terminal tail now pass through `redact.Text` like the block-event log already did.
```

```bash
cd /Users/omaraly/development/AI/Operator && git add frontend backend packages/terminal/CHANGELOG.md && git commit -m "operator: resolvePath/openPath/secretPatterns host seams, onHint and onBlockFinished actions, redaction pattern route

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

### Task 10: Measurement, the "Plan E landed" note, the closed and the new `TERMINAL.md` gaps

**Files:**
- Modify: `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md` (an "After Plan E" column on the baseline table; a "Plan E landed" paragraph after "Plan D landed")
- Modify: `TERMINAL.md` (§2 snapshot layout and checklist, §4.12, §5 — the wrapped-copy gap closed and the new gaps recorded, §6 the new bench command)
- Modify: `packages/terminal/CHANGELOG.md` (only if a measurement contradicts a line already written)

**Interfaces:**
- Consumes: `npm run bench:agent`, `bench:agent:gate`, `bench:agent:scroll`, `bench:feel`, `bench:glyphs`, `bench:affordances`, `bench:selection`; the Go `TestAgentSessionReplayReport`; every number's "After Plan D" cell in the spec's table.
- Produces: the documentation. Nothing executable.

No number in this task is invented. Every cell is copied from the command output of this HEAD after both wasm artifacts and the daemon were rebuilt. A flags-off regression against the "After Plan D" column beyond run-to-run noise is a **failure of Plan E**: stop, report it with the two outputs side by side, and do not tune anything to make it pass. A missed target is reported, not tuned.

- [ ] **Step 1: Measure**

From `/Users/omaraly/development/AI/Operator/packages/terminal`, after `npm run build:wasm -- --force && npm run build:ts`, the `vt-host` rebuild + copy, and `npm --prefix frontend run build:daemon`:

```bash
npm run bench:agent
npm run bench:agent:gate
npm run bench:agent:scroll
npm run bench:feel
npm run bench:selection
npm run bench:glyphs
npm run bench:affordances -- --action hover
npm run bench:affordances -- --action hint
npm run bench:affordances -- --action redact
cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... -run TestAgentSessionReplayReport -v
```

Copy from the JSON lines: `feedCost` and `feedSyncCost` medians at 1k/5k/50k with their `reached`/`samples`, `spinner` paints/addedNodes/rowNodesAdded, `tearing`, `longTask.queued`, `idlePanes.taskDurationS`, `selectionRepaint.rowsRepainted`, `reopen.{firstPaintMs,allRowsMs,rows}`, `rendererMemoryBytes`, `widthChange`, the scroll gate's coverage/trim/width lines, the feel gate's `PASS`, the selection gate's line, the Go test's mirror-memory figure, and each affordance run's report line.

**The two rows Plan E can move, and what to say about each:**
- `rendererMemoryBytes` — the sixth style word is +1 `u32` per exported run, and the link table is the URIs a session actually emitted. Report the number against Plan D's 11,730,944 bytes and say which of the two accounts for the delta (60,277 runs × 4 bytes ≈ 241 KB is the arithmetic; `claude-long-50k` emits no OSC 8, so the table should be empty — if the growth is far past ~241 KB, that is a finding).
- **The link table against the budget, stated explicitly.** `TerminalCore::memory_stats` and `Parser::trim_to` both weigh only content plus styles, so the registry is outside `Limits { bytes: 128 MiB }` and is never trimmed. Report `core.hyperlink_count()` and the table's byte size on the act-probe (which emits one OSC 8) and on `claude-long-50k` (which emits none), and state the worst case the caps permit as a fraction of the budget: 4096 × 2083 B ≈ 8.5 MB ≈ 6.6 % of 128 MiB, reachable only by a program printing 4096 distinct maximal URIs, and held for the life of the core. If a real session's table is anything but negligible, that is the finding.
- `feedCost` / `feedSyncCost` — OSC 8 parsing runs once per sequence, and a fixture with none should read unchanged. The block-timestamp fallback adds two `Option` writes per block boundary.

Everything else ("unchanged; Plan E does not touch it") is still measured and still copied.

- [ ] **Step 2: Fill the spec's table and the landed note**

Add an "After Plan E" column to the baseline table, each cell the flags-off number first, then "unchanged; Plan E does not touch it" with the number for the rows Plan E cannot move. Then, after the "Plan D landed" paragraph:

```markdown
Plan E landed <date>, measured on `development` HEAD (`<hash>`) after both wasm
artifacts and the daemon were rebuilt. Every affordance is additive: with no
pointer over the transcript, no chord typed and no host pattern list, a Claude
Code pane paints exactly what it painted on Plan D — `npm run bench:feel`
reports `PASS feel gate: zero pixel diff` on every fixture and on the new
`act-probe`.

| Affordance | Trigger | Host seam | Operator's implementation | Side-by-side |
|---|---|---|---|---|
| Logical-line copy | any copy | — | — | n/a (no visible change) |
| Link underline + open | pointer over a link; press with Cmd (macOS) / Ctrl | `openLink`, `openPath?`, `resolvePath?` | `open_external`; `open_path` (OS opener, line/column accepted and unused); `resolve_path` against the block's cwd or the session's workspace path | `baselines/act-probe/affordance-hover/` |
| Hint mode | Ctrl+Shift+Space, then a label | `onHint` | path → editor, URL → browser, anything else → clipboard | `baselines/act-probe/affordance-hint/` |
| OSC 8 hyperlinks | the agent emits them | — | opened through `openLink` like a detected URL | in the hover shots |
| Secret redaction | host patterns (Settings switch, default off) | `secretPatterns?` | the daemon's own built-in shapes over `GET /api/v1/redaction/patterns` | `baselines/act-probe/affordance-redact/` |
| Block timestamps | every block | `onBlockFinished` | one desktop notification for ≥ 10 s finished out of sight | n/a |

Measured rows: <feed cost, feed+sync, paints/s, nodes per paint, memory,
selection repaint, scroll, reopen, width change, torn frames, slow-link burst —
one line each, each either "unchanged within run-to-run noise" with the number
or the regression and its size>.

Affordance reports (from `npm run bench:affordances`): hover
<the four kinds>, hint <count and first labels>, redact <box count>.

Real-app verification (Task 9 Step 7): <what each of the six checks showed>.

Known gaps carried into `TERMINAL.md` §5: the OSC 8 registry is outside
`Limits { bytes }` — neither counted by `memory_stats` nor trimmed by
`trim_to` — and is never reclaimed, so a core holds up to ~8.5 MB of interned
URIs (4096 × 2083 B) above its 128 MiB budget for its lifetime; a reopened
pane's prepended rows are flagged `wrapped: false`, so a logical line the mirror wrapped before the reopen
still copies as several lines; a masked secret is masked in what the renderer
reads and paints, not in the row DOM, so the accessibility tree still carries
it; `openPath`'s line and column reach Operator and are dropped, because
`tauri-plugin-opener` takes no editor argument; the hint rule set is the
package's constant — a host cannot yet replace it (`hintBegin(rules)` accepts
one per call, nothing plumbs it through `TerminalSurface`).
```

- [ ] **Step 3: `TERMINAL.md`**

- §2 "Snapshot" bullet: the stride line becomes `stylePairs` (stride `STYLE_RUN_WORDS = 6`: `end, fg, bg, attrs, underline, link`); add `rowWrapped` (one byte per row, 1 when the next row continues this one) beside `rowIndents`, and `linkRanges`/`linkText` (the OSC 8 URI table, index `id - 1`) to the list; the checklist sentence gains `row_wrapped` beside `row_indents` as the worked example of a per-row field.
- §2, a new bullet **Logical lines**: two files own them and neither duplicates the other — `ts/core/src/logical-lines.ts` joins snapshot rows behind `TerminalCore.logicalLines(range)`, and `ts/renderer-dom/src/logical-lines.ts` lifts that join (`joinLogicalLine`, imported from the core) into the renderer's stable-row, per-block space with link runs attached. A change to how pieces join belongs in the core's `joinLogicalLine`; the renderer derives nothing of its own.
- §2, a new bullet **Hyperlinks**: `Parser::osc_dispatch` parses OSC 8 and interns it in `HyperlinkRegistry` (`crates/vt-core/src/hyperlink.rs`) with Warp's caps and no reclamation; the id rides in `CellStyle.link`, so it splits, merges, rewraps, evicts and trims with the styles; the mirror re-emits the sequence per run in the replay and in history chunks, because ids are per core. The **table is not** part of the byte budget: `trim_to` weighs content plus styles only (`parser.rs:629`), so the registry grows to its cap and stays — deliberate, bounded, and listed in §5.
- §2, the **BlockGrid** bullet: a block missing the hook's `start_ms`/`end_ms` is stamped from the clock of the feed that opened and closed it (`BlockGrid::set_clock`/`note_output`), and the TS core feeds with `Date.now()` so its stamps are epoch like the mirror's.
- §4.12: extend the entry — the arrow is still the default over the transcript, and the pointing hand appears only while the linkifier reports a link under the pointer (`.terminal-link-hover`), which is Warp's own rule (`app/src/terminal/view.rs` `set_cursor_shape`); the guard is `styles-parity.test.ts` "shows the pointing hand only while a link is under the pointer".
- §4.13: one sentence — the link underline, the hint labels and the redaction masks are overlays in `.terminal-decorations`, positioned from the same row geometry the selection fill uses, never edits to pooled row elements.
- §5: **delete** the "Copying a rewrapped block … joins rows with `\n`" gap — Task 1 closed it for the renderer's copy path (`readBlockOutput`/`vt_render` on the host side still join with `\n`; say so in the replacement line). Add the four gaps from Step 2's list.
- §6: add `npm run bench:affordances -- --action <hover|hint|redact>` (side-by-side screenshots of one affordance, never diffed) after `bench:feel -- --feature`.

- [ ] **Step 4: Re-run the baseline table's `feed()` and paint rows to show no regression**

```bash
cd /Users/omaraly/development/AI/Operator/packages/terminal && npm run bench:agent:gate
```

Copy the `feedCost`, `feedSyncCost`, `spinner` (paints/s, DOM nodes per paint, row nodes per paint) and `selectionRepaint` lines into the "After Plan E" column beside the "After Plan D" values. The gate asserts feed+sync flatness and the one-row selection repaint; if it fails, that is the report, not a number to adjust.

- [ ] **Step 5: Final verification and commit**

From `/Users/omaraly/development/AI/Operator/packages/terminal`: `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`; `npm run build:wasm -- --force && npm run build:ts && for p in core renderer-dom editor react; do (cd ts/$p && npx vitest run); done`; `npm run bench:selection`; `npm run bench:feel` → `PASS feel gate: zero pixel diff`; `cd /Users/omaraly/development/AI/Operator/backend && go test ./internal/adapters/runtime/ptyhost/... ./internal/redact/... ./internal/httpd/... ./internal/session_manager/...`; `cd /Users/omaraly/development/AI/Operator/frontend && npx tsc --noEmit -p . && npm run lint`; `cd /Users/omaraly/development/AI/Operator && npm --prefix frontend run build:daemon`.

```bash
cd /Users/omaraly/development/AI/Operator && git add docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md TERMINAL.md packages/terminal/CHANGELOG.md && git commit -m "docs: Plan E landed — affordances, their triggers and host seams, measurements, closed and new gaps

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Restart the daemon and the app.

---

## Self-review record (written with the plan)

- **Spec coverage, Part 5 bullet by bullet.** *Logical lines*: `TerminalCore.logicalLines(range)` joins rows flagged `wrapped`, which Task 1 exports per row through the incremental path, and `selection-text.ts` copies one line per logical line (Task 1) — the `TERMINAL.md` §5 gap, closed in Task 10. *Link grammar*: VS Code's `terminalLinkParsing.ts` ported with its own test table and attribution (Task 5), candidates validated through the new optional `HostCapabilities.resolvePath` (Tasks 6, 9). *Linkifier*: hover → per-logical-line providers, OSC 8 first and regex second, underline decoration, click with the platform modifier, pointing hand only over a link (Task 6). *Hint mode*: the chord labels every visible match of WezTerm's patterns minus IPFS plus Kitty's `path:line`, typing a label emits `onHint({ ruleId, text, path?, line? })`, labels from `compute_labels_for_alphabet` with WezTerm's own test table (Task 7). *OSC 8*: parsed in the core, interned with `MAX_DISTINCT_ENTRIES`/`MAX_URI_BYTES`, never reclaimed, exported so the renderer underlines and opens them (Tasks 2, 3, 6). *Secret redaction*: host-supplied patterns painted as masked highlights, honoured by copy and by the host's block-output reader, default off (Tasks 8, 9). *Block timestamps*: `startedAt`/`finishedAt` per block from the host clock passed with `feed_at` when the hook supplied none, and `onBlockFinished({ id, exitCode, durationMs, visible })` (Task 4). *"Additive UI only"*: every task ends with `npm run bench:feel` expecting `PASS feel gate: zero pixel diff`, and Tasks 6–8 add a side-by-side of their affordance instead of a pixel change. Nothing from Parts 1, 2, 3, 4 or 6 is touched.
- **Ordering.** The brief's order is followed exactly: wrapped export + logical lines + copy (1) → OSC 8 in the core and its export (2, one commit, plus 3 for the mirror it would otherwise strand) → block timestamps (4) → link grammar (5) → linkifier (6) → hint mode (7) → redaction (8) → Operator wiring (9) → measurement (10). The one addition is Task 3: Task 2 alone would leave a reopened pane without the links it had, which is a regression a reviewer would reject, and it is a `vt-host`/Go change rather than a core one, so it is its own commit.
- **Placeholders.** The angle-bracket fields in Tasks 9 and 10 are values the executor copies from command output at execution time (numbers, dates, hashes, the real-app results); they are not implementation gaps. Two test bodies in Task 9 Step 4 and Step 5 say to copy the neighbouring test's fixture by name and file — the fixtures are large, existing, and reading them is the work; the assertions are written in full. No step says "TBD", "similar to task N" or "appropriate handling".
- **Type consistency.** `rowWrapped` is `Vec<bool>` in `GridSnapshot`, `&[u8]` out of `ExportBuffers`, `Uint8Array` on `TerminalSnapshot`, `(blockId, row) => boolean` on `TextRows` — the same meaning (1 = the next row continues this one) in Tasks 1, 6, 7, 8 and 10. `LinkId`/`link` is `u16` in `CellStyle`, the sixth style word (`STYLE_RUN_WORDS = 6`, `STYLE_WORD_LINK = 5`) in Tasks 2, 3, 6 and 10; the URI table is `linkRanges`/`linkText` with index `id - 1` in Rust, the export and TS. `LinkRange` is `{ blockId, startRow, startCell, endRow, endCell }` with `endCell` exclusive in Tasks 6, 7 and 8; `rangeBoxes(range, rows, cellWidth, container)` has one signature everywhere. `DetectedLink`/`LinkProvider`/`LogicalLineView` are identical in `link-providers.ts`, `linkifier.ts`, the renderer and `TerminalSurface`. `HintEvent` is `{ ruleId, text, path?, line? }` in `hint-mode.ts`, `DomBlockRenderer.hintType`, the `onHint` prop and Operator's handler. `BlockFinishedEvent` is `{ id, exitCode, durationMs, visible }` in `block-finished.ts`, `onBlockFinished` on the renderer and the prop, and Operator's notification. `SecretPattern` is `{ source, flags? }` in `ts/core`, `compileSecretPatterns`, the `secretPatterns` capability, the daemon's `RedactionPattern` JSON and the bridge. `BLOCK_RECORD_WORDS = 18` with timestamps at words 14–17 matches Rust `write_blocks`, the vt-wasm test and `blocks.ts`. `resolvePath(path, cwd)` and `openPath(path, line?, column?)` have the same signature in `types.ts`, the path provider, `TerminalSurface`, `BlockTerminal` and the bridge.
