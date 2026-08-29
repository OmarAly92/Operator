# Warp Terminal Phase 1a Implementation Plan — `vt-core` blocks, the mark protocol, and the zsh bootstrap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `vt-core` from a flat row grid into a block-aware core that forms blocks from OSC 133 and our extension marks, and ship the protocol, both decoders, and the additive-only zsh bootstrap that feed it.

**Architecture:** Marks arrive in the byte stream. A tolerant decoder (`crates/marks`) turns them into lifecycle events; `BlockGrid` turns events into blocks over the existing `RowIndex`; a sum tree over those blocks answers viewport, selection and find queries in O(log n). The same protocol has a second decoder in Go (`go/marks`) so the daemon can record blocks with no client attached. Nothing in this phase renders.

**Tech Stack:** Rust 1.96.0 (`vte`, `unicode-width`, `regex-automata`), `wasm-bindgen` 0.2.127, Go 1.25.7, TypeScript 5 / Vitest, zsh.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`

**Phase split:** Phase 1 is split into 1a (this plan) and 1b (renderer, alt-screen handoff, daemon capture, Operator wiring). Spec §0.3 permits splitting by depth, not by order. See "Parallelism with Phase 1b" below — **Task 1 is the gate that unblocks 1b**.

## Global Constraints

Copied verbatim from the spec and from Phase 0's landed conventions. Every task's requirements implicitly include this section.

- **No file over 600 lines.** `npm --prefix packages/terminal run check:boundaries` enforces it for `.ts .tsx .js .mjs .cjs .rs .go .sh .fish .ps1`.
- **No import may escape `packages/terminal/`.** Same checker. The package MUST NOT import from `frontend/`, `backend/`, or `packages/shared/`.
- **`renderer-dom` MUST NOT import `editor` or `completions`; `editor` MUST NOT import `completions`.** Same checker.
- **OSC 133 is the baseline; our extension is additive** (spec §2.6, §7.2). There MUST NOT be a code path where an extension mark is required to close a block.
- **One extension encoding only:** `OSC 7000 ; <key>=<value> ; ... ST`, values percent-encoded, unknown keys ignored, `v=<n>` version key (spec §7.3). Do not add a second encoding.
- **The block state machine is a tolerant parser** (spec §7.4). Never assume marks are paired.
- **Additive-only shell integration** (spec §8): never remove or reorder the user's hooks, never touch a keybinding, never name a third-party prompt framework, never execute anything in the user's session for bookkeeping, never inspect ssh argv.
- **Prompt suppression stays OFF in Phase 1** (spec §8.1, §14.0, wrong turn 16).
- **Use `vte` from crates.io. MUST NOT fork it** (spec §6.3b).
- **No comments that restate the code.** Match the neighbours: Phase 0's Rust comments explain *why*, never *what*.
- Rust: `cargo fmt --check` clean, `cargo clippy --workspace --all-targets -- -D warnings` clean.
- Go: module `github.com/OmarAly92/operator/packages/terminal/go/marks`, `go 1.25.7`, standard library only.

---

## Parallelism with Phase 1b

**Answer: they can run in parallel, after Task 1 lands — not before.**

Phase 1b consumes three things from 1a:

| 1b needs | 1a task | Nature |
| --- | --- | --- |
| the block buffers in `TerminalSnapshot` | Task 1 | shape only |
| `BlockState` / `BlockSource` / `BlockView` types | Task 1 | shape only |
| `go/marks` decoder for the daemon | Task 6 | real code |

The first two are **interface**, not implementation. Task 1 therefore freezes the entire block-facing contract and ships it behind a stub that emits one synthetic block — exactly what Phase 0 already renders. The moment Task 1 merges to master, 1b can fork its own worktree and build the renderer against the frozen types with real, if trivial, data flowing.

**Recommended sequencing:**

1. Execute Task 1 in a `phase-1a` worktree. Merge that one commit to master.
2. Fork a `phase-1b` worktree from that master commit. 1a continues from Task 2 in its own worktree.
3. 1b builds the renderer, virtualization and block headers against the frozen contract.
4. 1b's daemon-capture task waits for Task 6 to merge, or stubs the decoder behind an interface and swaps it.
5. Both merge. 1b's fake core is replaced by the real one.

**What cannot be parallel, and must run after both merge:**

- the perf gate (spec §9.4) and the 50,000-block 60fps criterion — they need the real core and the real renderer together;
- the "usable as the daily driver" acceptance (spec §14.0);
- the zero-clients and two-clients block capture tests.

**The risk you are accepting:** if 1a finds the frozen layout wrong, 1b eats the churn. Task 1 mitigates it by making the layout generous — every field the spec's §6.3 `Block` names is in the contract from the start, including ones 1a only fills in at Task 7 — and by reusing the existing `generation` counter as the invalidation signal so no new synchronisation is invented.

**Merge conflicts are not the risk.** 1a touches `crates/`, `protocol/`, `go/`, `shell/`; 1b touches `ts/renderer-dom/`, `ts/react/`, `frontend/`, `backend/`. The only shared file is `ts/core/src/types.ts`, which Task 1 finishes.

---

## Findings That Shape This Plan

**1. `RowIndex` already does half the job.** `crates/vt-core/src/row_index.rs` keeps completed rows plus an open row, and `trim_to` returns the earliest retained offset. Blocks are ranges *over rows*, so `BlockGrid` sits on top of `RowIndex` and never touches `Content` directly.

**2. Trimming must drop blocks, not just rows.** Once blocks exist, a block whose rows have all been trimmed must leave the sum tree in the same pass, or the tree's summaries drift from the row index. Task 3 owns this, and it is the same class of bug as the Phase 0 review finding in `row_index.rs`.

**3. The snapshot is rebuilt in full on every feed.** `TerminalCore::feed` calls `build_snapshot` after every `advance`. Acceptable at Phase 0 scale, not acceptable at 50,000 blocks. Task 7 keeps row and content export as-is and adds block records beside them; the renderer asks for the rows of the blocks it paints. **Do not attempt an incremental snapshot in this phase** — that is a Phase 1b/4 decision driven by the perf gate.

**4. `checked_u32` exists and must be used.** `crates/vt-core/src/grid.rs` exports `pub(crate) fn checked_u32(usize) -> Result<u32, CoreError>`. Every new offset crossing into an export buffer goes through it. `CoreError::OffsetOverflow` already maps to a `JsError`.

**5. Warp parses OSC 133 and throws it away.** `crates/warp_terminal/src/model/ansi/mod.rs:1019-1026` dispatches `b"133"` to a `PromptMarker` that is not a block source, and `crates/warp_terminal/src/local_tty/shell.rs:691-694` *disables* fish's OSC 133 because fish emits `133;A` with no `133;B`. Task 5's recovery table exists to make exactly that stream produce correct blocks.

**6. Two Warp files are reference, not model.** `app/src/terminal/model/blocks.rs` (4,262 lines) and `block.rs` (3,502) carry UI state inside the block model. Read them for block identity and indexing; keep presentation out of `vt-core`.

---

## Planned File Structure

```
packages/terminal/
  protocol/
    SPEC.md                     normative protocol document
    README.md                   how to change the protocol
    vectors/*.json              conformance vectors, read by BOTH decoders
    fuzz-corpus/*.bin           seeds incl. unpaired, split, interleaved marks
  crates/
    marks/src/
      lib.rs                    public decode surface
      event.rs                  MarkEvent, MarkTier
      scanner.rs                byte scanner tolerant of split reads
      osc.rs                    OSC 133 + OSC 7 (tier 1)
      extension.rs              OSC 7000 key/value (tier 2)
    vt-core/src/
      block.rs                  Block, BlockId, BlockState, BlockSource, BlockMeta
      block_tree.rs             sum tree + BlockSummary
      block_grid.rs             blocks over RowIndex, fed by MarkEvent
      block_selection.rs        selection in (BlockId, row, column)
      find.rs                   incremental cancellable search
      alt_screen.rs             tracked alt-screen state
  go/marks/
    go.mod
    marks.go, scanner.go        decoder
    marks_test.go               runs protocol/vectors
  shell/
    zsh.sh                      additive-only bootstrap
    README.md                   what it does and refuses to do
```

Modified: `crates/vt-core/src/{lib.rs,parser.rs,grid.rs}`, `crates/vt-core/Cargo.toml`, `crates/vt-wasm/src/lib.rs`, `ts/core/src/{types.ts,terminal-core.ts,index.ts}`, `packages/terminal/{Cargo.toml,CHANGELOG.md,README.md}`, `.github/workflows/terminal.yml`.

---

### Task 1: Freeze the block export contract behind a stub

This is the task Phase 1b waits on. Merge it to master on its own.

**Files:**
- Create: `packages/terminal/crates/vt-core/src/block.rs`
- Modify: `packages/terminal/crates/vt-core/src/{lib.rs,grid.rs}`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Create: `packages/terminal/ts/core/src/blocks.ts`
- Modify: `packages/terminal/ts/core/src/{types.ts,terminal-core.ts,index.ts}`
- Test: `packages/terminal/crates/vt-core/tests/block_contract.rs`
- Test: `packages/terminal/ts/core/src/block-contract.test.ts`

**Interfaces:**
- Produces `vt_core::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan}`.
- Produces `GridSnapshot::{blocks: Vec<BlockRecord>, block_text: Vec<u8>}` plus `block_command`, `block_cwd`, `block_branch`.
- Produces `WasmTerminalCore::{blocks_ptr, blocks_len, block_text_ptr, block_text_len}`.
- Produces TypeScript `TerminalSnapshot.{blocks: Uint32Array, blockText: Uint8Array}`, `BlockView`, `BLOCK_RECORD_WORDS`, `decodeBlocks`.

- [ ] **Step 1: Write the Rust contract test**

Create `packages/terminal/crates/vt-core/tests/block_contract.rs`:

```rust
use vt_core::{BlockSource, BlockState, TerminalCore};

#[test]
fn a_fresh_core_reports_one_synthetic_block_covering_every_row() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"alpha\nbravo");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    let block = &snapshot.blocks[0];
    assert_eq!(block.first_row, 0);
    assert_eq!(block.row_count, snapshot.row_count() as u32);
    assert_eq!(block.state, BlockState::Running);
    assert_eq!(block.source, BlockSource::Synthetic);
    assert_eq!(block.exit_code, None);
    assert_eq!(snapshot.block_command(0), "");
    assert_eq!(snapshot.block_cwd(0), "");
}

#[test]
fn block_ids_are_stable_across_feeds() {
    let mut core = TerminalCore::new(20, 100).unwrap();
    core.feed(b"one\n");
    let first = core.snapshot().unwrap().blocks[0].id;
    core.feed(b"two\n");
    assert_eq!(core.snapshot().unwrap().blocks[0].id, first);
}
```

- [ ] **Step 2: Run it and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core --test block_contract`
Expected: FAIL — `BlockState` and `snapshot.blocks` do not exist.

- [ ] **Step 3: Define the block types**

Create `packages/terminal/crates/vt-core/src/block.rs`:

```rust
pub type BlockId = u64;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockState {
    Running,
    Finished,
    Abandoned,
}

/// Which tier of marks produced this block.
///
/// The renderer and the tests both branch on it: a zero-setup OSC 133 session
/// and a fully bootstrapped one must be distinguishable without guessing.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockSource {
    Osc133,
    Extension,
    Synthetic,
}

impl BlockState {
    pub fn as_u32(self) -> u32 {
        match self {
            BlockState::Running => 0,
            BlockState::Finished => 1,
            BlockState::Abandoned => 2,
        }
    }
}

impl BlockSource {
    pub fn as_u32(self) -> u32 {
        match self {
            BlockSource::Osc133 => 0,
            BlockSource::Extension => 1,
            BlockSource::Synthetic => 2,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct BlockMeta {
    pub command: String,
    pub cwd: String,
    pub git_branch: String,
    pub exit_code: Option<i32>,
    pub started_at_ms: Option<u64>,
    pub finished_at_ms: Option<u64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Block {
    pub id: BlockId,
    pub first_row: usize,
    pub row_count: usize,
    pub state: BlockState,
    pub source: BlockSource,
    pub meta: BlockMeta,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct TextSpan {
    pub start: u32,
    pub end: u32,
}

/// One block as the snapshot carries it: every field already narrowed to the
/// `u32` the export buffers use, and text hoisted into `block_text` so the
/// record stays fixed width.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BlockRecord {
    pub id: BlockId,
    pub first_row: u32,
    pub row_count: u32,
    pub state: BlockState,
    pub source: BlockSource,
    pub exit_code: Option<i32>,
    pub duration_ms: Option<u64>,
    pub command: TextSpan,
    pub cwd: TextSpan,
    pub git_branch: TextSpan,
}
```

Add `pub mod block;` and `pub use block::{Block, BlockId, BlockMeta, BlockRecord, BlockSource, BlockState, TextSpan};` to `lib.rs`.

- [ ] **Step 4: Emit one synthetic block from the snapshot**

In `grid.rs`, extend `GridSnapshot` and add the text accessors:

```rust
pub struct GridSnapshot {
    pub content: Vec<u8>,
    pub rows: Vec<(u32, u32)>,
    pub run_ranges: Vec<(u32, u32)>,
    pub style_pairs: Vec<(u32, StyleCode)>,
    pub blocks: Vec<BlockRecord>,
    pub block_text: Vec<u8>,
}

impl GridSnapshot {
    pub fn block_command(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].command)
    }

    pub fn block_cwd(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].cwd)
    }

    pub fn block_branch(&self, index: usize) -> &str {
        self.span_text(self.blocks[index].git_branch)
    }

    fn span_text(&self, span: TextSpan) -> &str {
        std::str::from_utf8(&self.block_text[span.start as usize..span.end as usize])
            .expect("block text is valid utf-8")
    }
}
```

At the end of `build_snapshot`, before the `Ok(...)`, build the stub. **Task 7 replaces this whole expression with the real `BlockGrid` projection and nothing else in this file changes then.**

```rust
    let blocks = vec![BlockRecord {
        id: 0,
        first_row: 0,
        row_count: checked_u32(row_ranges.len())?,
        state: BlockState::Running,
        source: BlockSource::Synthetic,
        exit_code: None,
        duration_ms: None,
        command: TextSpan::default(),
        cwd: TextSpan::default(),
        git_branch: TextSpan::default(),
    }];
    let block_text: Vec<u8> = Vec::new();
```

- [ ] **Step 5: Run the Rust contract test**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core --test block_contract`
Expected: PASS (2 tests).

- [ ] **Step 6: Export the block buffers through `vt-wasm`**

In `crates/vt-wasm/src/lib.rs`, add `blocks: Vec<u32>` and `block_text: Vec<u8>` to `ExportBuffers`, and flatten each `BlockRecord` into exactly **fourteen** `u32` words, in this order:

| Word | Meaning |
| --- | --- |
| 0, 1 | `id` low 32 bits, high 32 bits |
| 2 | `first_row` |
| 3 | `row_count` |
| 4 | `state.as_u32() \| (source.as_u32() << 8)` |
| 5 | `exit_code`: `0` for `None`, otherwise `(exit + 1) as u32` |
| 6, 7 | `duration_ms` low, high — both `u32::MAX` means `None` |
| 8, 9 | `command.start`, `command.end` |
| 10, 11 | `cwd.start`, `cwd.end` |
| 12, 13 | `git_branch.start`, `git_branch.end` |

Add `pub const BLOCK_RECORD_WORDS: usize = 14;` and export it. Guard `block_text.len()` with `checked_u32_from_u64` exactly as the content buffer already is. Add the four accessors beside the existing pointer/length pairs, following their shape exactly.

- [ ] **Step 7: Write the TypeScript contract test**

Create `packages/terminal/ts/core/src/block-contract.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { BLOCK_RECORD_WORDS, createTerminalCore, decodeBlocks, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

describe("block export contract", () => {
	it("exposes one synthetic block covering every row", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.feed(new TextEncoder().encode("alpha\nbravo"));
		const snapshot = core.snapshot();

		expect(snapshot.blocks.length).toBe(BLOCK_RECORD_WORDS);
		const blocks = decodeBlocks(snapshot);
		expect(blocks).toHaveLength(1);
		expect(blocks[0].firstRow).toBe(0);
		expect(blocks[0].rowCount).toBe(snapshot.rows.length / 2);
		expect(blocks[0].state).toBe("running");
		expect(blocks[0].source).toBe("synthetic");
		expect(blocks[0].exitCode).toBeNull();
		expect(blocks[0].durationMs).toBeNull();
		expect(blocks[0].command).toBe("");
	});

	it("gives every block a stable string id", () => {
		const core = createTerminalCore({ columns: 20, scrollback: 100 });
		core.feed(new TextEncoder().encode("one\n"));
		const first = decodeBlocks(core.snapshot())[0].id;
		core.feed(new TextEncoder().encode("two\n"));
		expect(decodeBlocks(core.snapshot())[0].id).toBe(first);
		expect(typeof first).toBe("string");
	});
});
```

- [ ] **Step 8: Run it and confirm red**

Run: `npm --prefix packages/terminal run build:wasm && npx vitest run --root packages/terminal/ts/core block-contract`
Expected: FAIL — `decodeBlocks` is not exported.

- [ ] **Step 9: Add the TypeScript decode surface**

In `ts/core/src/types.ts` add:

```ts
export type BlockState = "running" | "finished" | "abandoned";

export type BlockSource = "osc133" | "extension" | "synthetic";

export type BlockView = Readonly<{
	id: BlockId;
	firstRow: number;
	rowCount: number;
	state: BlockState;
	source: BlockSource;
	exitCode: number | null;
	durationMs: number | null;
	command: string;
	cwd: string;
	gitBranch: string;
}>;
```

Extend `TerminalSnapshot` with `blocks: Uint32Array` and `blockText: Uint8Array`, read in `terminal-core.ts` exactly like the existing buffers, and validate `blocks.length % BLOCK_RECORD_WORDS === 0` beside the existing `validateEvenLength` calls.

Create `ts/core/src/blocks.ts` with `BLOCK_RECORD_WORDS` and `decodeBlocks`. **`BlockId` stays a string**: the Rust id is a `u64` and a JavaScript number cannot hold one, so `decodeBlocks` composes it as `` `${high}:${low}` ``. Re-export both from `index.ts`.

- [ ] **Step 10: Run every gate**

```bash
cargo test --manifest-path packages/terminal/Cargo.toml --workspace
cargo fmt --manifest-path packages/terminal/Cargo.toml --all --check
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
```

Expected: all exit 0, and every Phase 0 test still passes unchanged.

- [ ] **Step 11: Commit, then merge to master before starting Task 2**

```bash
git add packages/terminal
git commit -m "feat(terminal): freeze the block export contract"
```

Merge this single commit to master so Phase 1b can fork from it. Do not continue to Task 2 until that merge lands.

---

### Task 2: Sum tree over blocks

**Files:**
- Create: `packages/terminal/crates/vt-core/src/block_tree.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`

**Interfaces:**
- Consumes `Block`, `BlockId`, `BlockMeta`, `BlockSource`, `BlockState` (Task 1).
- Produces `BlockSummary { blocks: usize, rows: usize }` and `BlockTree::{new, push, pop_front, len, summary, find_by_row, iter}`.

Reference: `crates/sum_tree/src/{lib.rs,cursor.rs}` in Warp (532 + 1,010 lines) for the summary/cursor design. Ours is **not generic** — it carries `BlockSummary` directly, which is why it is a fraction of the size.

- [ ] **Step 1: Write the unit tests**

At the bottom of `block_tree.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::block::{BlockMeta, BlockSource, BlockState};

    fn block(id: BlockId, first_row: usize, row_count: usize) -> Block {
        Block {
            id,
            first_row,
            row_count,
            state: BlockState::Finished,
            source: BlockSource::Osc133,
            meta: BlockMeta::default(),
        }
    }

    #[test]
    fn summary_matches_a_naive_recomputation_after_any_mutation() {
        let mut tree = BlockTree::new();
        for index in 0..500usize {
            tree.push(block(index as u64, index * 3, 3));
        }
        for _ in 0..137 {
            tree.pop_front();
        }
        let naive_rows: usize = tree.iter().map(|b| b.row_count).sum();
        assert_eq!(tree.summary().rows, naive_rows);
        assert_eq!(tree.summary().blocks, tree.len());
        assert_eq!(tree.len(), 363);
    }

    #[test]
    fn find_by_row_returns_the_block_containing_that_row() {
        let mut tree = BlockTree::new();
        tree.push(block(1, 0, 4));
        tree.push(block(2, 4, 1));
        tree.push(block(3, 5, 10));

        assert_eq!(tree.find_by_row(0).map(|b| b.id), Some(1));
        assert_eq!(tree.find_by_row(3).map(|b| b.id), Some(1));
        assert_eq!(tree.find_by_row(4).map(|b| b.id), Some(2));
        assert_eq!(tree.find_by_row(14).map(|b| b.id), Some(3));
        assert_eq!(tree.find_by_row(15).map(|b| b.id), None);
    }

    #[test]
    fn find_by_row_is_correct_after_front_removal() {
        let mut tree = BlockTree::new();
        tree.push(block(1, 0, 4));
        tree.push(block(2, 4, 6));
        tree.pop_front();
        assert_eq!(tree.find_by_row(4).map(|b| b.id), Some(2));
        assert_eq!(tree.find_by_row(0).map(|b| b.id), None);
    }

    #[test]
    fn an_empty_tree_has_a_zero_summary() {
        let tree = BlockTree::new();
        assert_eq!(tree.len(), 0);
        assert_eq!(tree.summary(), BlockSummary::default());
        assert!(tree.find_by_row(0).is_none());
    }

    #[test]
    fn a_hundred_thousand_blocks_answer_row_queries_without_scanning() {
        let mut tree = BlockTree::new();
        for index in 0..100_000usize {
            tree.push(block(index as u64, index, 1));
        }
        assert_eq!(tree.find_by_row(99_999).map(|b| b.id), Some(99_999));
        assert_eq!(tree.summary().rows, 100_000);
    }
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_tree`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement the tree**

A B-tree with `const TREE_BASE: usize = 6` (Warp's fan-out). Internal nodes cache the summed `BlockSummary` of their children; leaves hold up to `2 * TREE_BASE` blocks.

```rust
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct BlockSummary {
    pub blocks: usize,
    pub rows: usize,
}

impl BlockSummary {
    fn of(block: &Block) -> Self {
        Self { blocks: 1, rows: block.row_count }
    }

    fn add(self, other: Self) -> Self {
        Self {
            blocks: self.blocks + other.blocks,
            rows: self.rows + other.rows,
        }
    }
}
```

`find_by_row(row)` descends by comparing `row` against the running row summary, so it is O(log n) and never scans. `push` appends at the back and `pop_front` removes at the front — the only two mutations a terminal needs, because it appends and trims.

If node splitting pushes the file past 600 lines, move the node type into `block_tree/node.rs` rather than shortening the code.

- [ ] **Step 4: Run the tests**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_tree`
Expected: PASS (5 tests). The 100,000-block test should finish in well under a second; a linear implementation still passes but slowly, and that timing is the smoke signal.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): add the block sum tree"
```

---

### Task 3: The block grid over `RowIndex`

**Files:**
- Create: `packages/terminal/crates/vt-core/src/block_grid.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`

**Interfaces:**
- Consumes `BlockTree`, `BlockSummary` (Task 2) and the Task 1 block types.
- Produces `BlockGrid::{new, open_block, close_block, note_row_completed, set_meta_field, trim_to_first_row, blocks, is_empty}`.

- [ ] **Step 1: Write the unit tests**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opening_a_block_closes_the_previous_one_as_abandoned() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.open_block(BlockSource::Osc133);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0].state, BlockState::Abandoned);
        assert_eq!(blocks[1].state, BlockState::Running);
    }

    #[test]
    fn closing_records_the_exit_code_and_marks_finished() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.close_block(Some(3));
        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks[0].state, BlockState::Finished);
        assert_eq!(blocks[0].meta.exit_code, Some(3));
    }

    #[test]
    fn closing_with_no_open_block_is_ignored() {
        let mut grid = BlockGrid::new();
        grid.close_block(Some(0));
        assert_eq!(grid.blocks().count(), 0);
    }

    #[test]
    fn trimming_drops_blocks_whose_rows_are_all_gone() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();
        grid.note_row_completed();
        grid.close_block(Some(0));
        grid.open_block(BlockSource::Osc133);
        grid.note_row_completed();

        grid.trim_to_first_row(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0, "surviving rows renumber from zero");
    }

    #[test]
    fn a_partially_trimmed_block_keeps_its_surviving_rows() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        for _ in 0..5 {
            grid.note_row_completed();
        }
        grid.trim_to_first_row(2);

        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].first_row, 0);
        assert_eq!(blocks[0].row_count, 3);
    }

    #[test]
    fn extension_fields_upgrade_the_open_block_source() {
        let mut grid = BlockGrid::new();
        grid.open_block(BlockSource::Osc133);
        grid.set_meta_field("cmd", "git status");
        let blocks: Vec<_> = grid.blocks().collect();
        assert_eq!(blocks[0].source, BlockSource::Extension);
        assert_eq!(blocks[0].meta.command, "git status");
    }
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_grid`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement `BlockGrid`**

It owns a `BlockTree` of closed blocks, an optional open block, and a monotonic `next_id`. Row indices are **relative to the oldest retained row**, which is why `trim_to_first_row` renumbers: `Parser::trim_to` already discards rows from the front, and a block index that did not renumber would drift from `RowIndex` on the first trim.

`trim_to_first_row(first_row)` pops whole blocks off the front while `block.first_row + block.row_count <= first_row`, then subtracts `first_row` from every survivor, clamping the front block's `row_count` when the cut lands inside it.

`set_meta_field(key, value)` accepts the tier-2 keys `cmd`, `cwd`, `branch`, `exit`, `start_ms`, `end_ms`, ignores any other key, and sets `source = BlockSource::Extension` on the open block whenever it accepts one.

**Renumbering every survivor is O(n) and that is deliberate for this phase.** Trimming runs once per feed and only past the row cap; making it O(log n) needs a root-level offset, which is an optimisation the perf gate has not asked for. Do not add it now — record it in the CHANGELOG at Task 11 instead.

- [ ] **Step 4: Run the tests**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_grid`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): add the block grid over the row index"
```

---

### Task 4: The protocol document, vectors, and fuzz corpus

**Files:**
- Create: `packages/terminal/protocol/SPEC.md`
- Create: `packages/terminal/protocol/README.md`
- Create: `packages/terminal/protocol/vectors/*.json`
- Create: `packages/terminal/protocol/fuzz-corpus/*.bin`

**Interfaces:**
- Produces the vector file format both decoders read. Control bytes are written as JSON unicode escapes (`\u001b` for ESC, `\u0007` for BEL) so every vector file stays printable and diffable; each decoder decodes `input` to bytes before feeding. `events` lists mark events only — literal text between marks is not an event.

```json
{
  "name": "osc133-happy-path",
  "input": "\u001b]133;A\u0007$ \u001b]133;B\u0007ls -la\u001b]133;C\u0007total 0\n\u001b]133;D;0\u0007",
  "events": [
    { "kind": "prompt_start", "tier": 1 },
    { "kind": "command_start", "tier": 1 },
    { "kind": "output_start", "tier": 1 },
    { "kind": "command_end", "tier": 1, "exitCode": 0 }
  ]
}
```

- [ ] **Step 1: Write `SPEC.md`**

State normatively:

- **Tier 1:** `OSC 133 ; A`, `; B`, `; C`, `; D`, `; D ; <exit>`; and `OSC 7 ; file://host/path` for the working directory.
- **Terminators:** both BEL (`0x07`) and ST (ESC followed by backslash) are accepted for every OSC. A decoder handling only one will miss half the shells in the wild.
- **Tier 2:** `OSC 7000 ; key=value ; key=value ST`, every value percent-encoded, `v=1` required, unknown keys ignored individually, a higher major version ignoring the mark whole.
- **Keys defined in this phase:** `v`, `id`, `cmd`, `cwd`, `branch`, `exit`, `start_ms`, `end_ms`.
- **Reserved, and MUST NOT be emitted by Phase 1a:** `input-ready`, `input-released`. They are Phase 2's line-editor signal (spec §3.5, §10.2); naming them here stops the key space being reused.
- **The full §7.4 recovery table, copied verbatim from the design spec.**

- [ ] **Step 2: Write one vector per recovery-table row**

Create exactly these under `protocol/vectors/`:

`osc133-happy-path.json`, `osc133-st-terminator.json`, `a-with-block-already-open.json`, `b-with-no-preceding-a.json`, `c-with-no-preceding-b.json`, `d-with-no-open-block.json`, `d-with-missing-exit.json`, `a-immediately-after-a.json`, `unknown-133-subcommand.json`, `unknown-7000-key.json`, `malformed-truncated-sequence.json`, `output-with-no-marks.json`, `osc7-cwd.json`, `extension-full-block.json`, `extension-higher-version-ignored.json`, `percent-encoded-values.json`.

`a-immediately-after-a.json` is the regression for `crates/warp_terminal/src/local_tty/shell.rs:691-694` — fish emitting `133;A` with no `133;B`, which Warp's fix was to switch OSC 133 off entirely. Its expected events are two `prompt_start`s, and Task 7's state machine must turn that into one abandoned block plus one running block.

- [ ] **Step 3: Seed the fuzz corpus**

Raw byte files under `protocol/fuzz-corpus/`: every vector's decoded `input`, plus one file per hazard — a mark split across a read boundary, marks interleaved with SGR inside a `B`/`C` pair, marks interleaved with the alt-screen switch, an OSC that never terminates, and 64 KiB of repeated ESC-`]` pairs.

- [ ] **Step 4: Write `README.md`**

One page: what the directory is, that both decoders MUST pass every vector, that changing the protocol means changing the vectors first so both decoders fail together, and that a decoder passing the vectors while panicking on a split-read input is not done — PTY reads split wherever they like.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/protocol
git commit -m "docs(terminal): define the mark protocol, vectors, and fuzz corpus"
```

---

### Task 5: The Rust decoder, `crates/marks`

**Files:**
- Modify: `packages/terminal/crates/marks/Cargo.toml`
- Modify: `packages/terminal/crates/marks/src/lib.rs`
- Create: `packages/terminal/crates/marks/src/{event.rs,scanner.rs,osc.rs,extension.rs,testing.rs}`
- Test: `packages/terminal/crates/marks/tests/vectors.rs`
- Create: `packages/terminal/fuzz/fuzz_targets/decode.rs`

**Interfaces:**
- Produces `marks::{MarkDecoder, MarkEvent, MarkTier, ExtensionFields}` and `marks::testing::load_vector`.
- `MarkDecoder::feed(&mut self, bytes: &[u8]) -> Vec<MarkEvent>` is **stateful across calls**, so a mark split across two feeds still decodes.

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MarkTier {
    Osc133,
    Extension,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MarkEvent {
    PromptStart { tier: MarkTier },
    CommandStart { tier: MarkTier },
    OutputStart { tier: MarkTier },
    CommandEnd { tier: MarkTier, exit_code: Option<i32> },
    CwdChanged { path: String },
    Extension(ExtensionFields),
    AltScreenEnter,
    AltScreenLeave,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ExtensionFields {
    pub pairs: Vec<(String, String)>,
}
```

- [ ] **Step 1: Write the vector-driven test**

Create `packages/terminal/crates/marks/tests/vectors.rs`:

```rust
use std::fs;
use std::path::PathBuf;

use marks::{MarkDecoder, MarkEvent, MarkTier};

fn vectors_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../protocol/vectors")
}

#[test]
fn every_vector_decodes_to_its_expected_events() {
    let mut checked = 0;
    for entry in fs::read_dir(vectors_dir()).expect("protocol/vectors exists") {
        let path = entry.unwrap().path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let vector = marks::testing::load_vector(&path);
        let actual = MarkDecoder::new().feed(&vector.input);
        assert_eq!(actual, vector.events, "vector {}", vector.name);
        checked += 1;
    }
    assert!(checked >= 16, "expected the full vector set, found {checked}");
}

#[test]
fn a_mark_split_across_two_feeds_still_decodes() {
    let mut decoder = MarkDecoder::new();
    assert_eq!(decoder.feed(b"\x1b]133;"), vec![]);
    assert_eq!(
        decoder.feed(b"A\x07"),
        vec![MarkEvent::PromptStart { tier: MarkTier::Osc133 }]
    );
}

#[test]
fn a_mark_split_byte_by_byte_still_decodes() {
    let mut decoder = MarkDecoder::new();
    let mut events = Vec::new();
    for byte in b"\x1b]133;D;7\x07" {
        events.extend(decoder.feed(&[*byte]));
    }
    assert_eq!(
        events,
        vec![MarkEvent::CommandEnd { tier: MarkTier::Osc133, exit_code: Some(7) }]
    );
}

#[test]
fn an_unterminated_osc_does_not_swallow_later_marks_forever() {
    let mut decoder = MarkDecoder::new();
    let _ = decoder.feed(b"\x1b]133;");
    let _ = decoder.feed(&vec![b'y'; 128 * 1024]);
    let events = decoder.feed(b"\x1b]133;A\x07");
    assert_eq!(events, vec![MarkEvent::PromptStart { tier: MarkTier::Osc133 }]);
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p marks`
Expected: FAIL — `MarkDecoder` does not exist.

- [ ] **Step 3: Implement the scanner**

`scanner.rs` holds a bounded pending buffer:

- an OSC begins at ESC `]` and ends at BEL or at ESC backslash;
- bytes outside a sequence are passed over, never buffered;
- the pending buffer is capped at **4096 bytes**; on overflow the scanner abandons the sequence, emits nothing, and returns to scanning.

That cap is what makes the fourth test pass. Without it an unterminated OSC turns the decoder into an unbounded sink and a permanent black hole — a TUI that emits one would silently kill block detection for the rest of the session.

- [ ] **Step 4: Implement the tier-1 decoders**

`osc.rs` parses `133;A`, `133;B`, `133;C`, `133;D`, `133;D;<exit>` and `7;file://host/path`. An unknown `133` subcommand yields **no event** (recovery row 7). A `D` with an unparseable exit yields `CommandEnd { exit_code: None }`, never an error. Alt-screen enter and leave come from the CSI `?1049h` / `?1049l` sequences, which the scanner recognises alongside OSC.

- [ ] **Step 5: Implement the tier-2 decoder**

`extension.rs` parses `7000;k=v;k=v`, percent-decoding each value. It reads `v` first; if the major version exceeds 1 it returns no event at all — the whole mark is ignored (spec §7.3). Unknown keys are skipped individually.

`serde_json` is a **dev-dependency only**, used by `testing::load_vector`. The decoder itself stays dependency-free so the daemon-side crate and the wasm build stay small.

- [ ] **Step 6: Run the vector suite**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p marks`
Expected: PASS, with the vector test reporting at least 16 vectors checked.

- [ ] **Step 7: Add the fuzz target**

```bash
cargo install cargo-fuzz --version 0.13.1 --locked
cd packages/terminal && cargo fuzz init --fuzz-dir fuzz
```

`fuzz/fuzz_targets/decode.rs`:

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use marks::MarkDecoder;

fuzz_target!(|data: &[u8]| {
    let mut decoder = MarkDecoder::new();
    for chunk in data.chunks(7) {
        let _ = decoder.feed(chunk);
    }
});
```

Chunking by seven is deliberate: it forces marks to split across feeds at offsets no hand-written test would pick.

Seed `fuzz/corpus/decode` from `protocol/fuzz-corpus/`, then run:

`cargo fuzz run decode fuzz/corpus/decode -- -runs=200000 -max_len=8192`

Expected: no crash, no OOM, no timeout.

Add only `fuzz/target` and `fuzz/artifacts` to `packages/terminal/.gitignore`; commit `fuzz/Cargo.toml`, `fuzz/fuzz_targets/` and the seed corpus.

- [ ] **Step 8: Run the gates and commit**

```bash
cargo fmt --manifest-path packages/terminal/Cargo.toml --all --check
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
npm --prefix packages/terminal run check:boundaries
git add packages/terminal
git commit -m "feat(terminal): add the tolerant Rust mark decoder"
```

---

### Task 6: The Go decoder, `go/marks`

**Files:**
- Create: `packages/terminal/go/marks/go.mod`
- Create: `packages/terminal/go/marks/marks.go`
- Create: `packages/terminal/go/marks/scanner.go`
- Test: `packages/terminal/go/marks/marks_test.go`

**Interfaces:**
- Consumes `packages/terminal/protocol/vectors/*.json` (Task 4).
- Produces:

```go
package marks

type Tier int

const (
	TierOSC133    Tier = 1
	TierExtension Tier = 2
)

type Event struct {
	Kind     string
	Tier     Tier
	ExitCode *int
	Path     string
	Fields   map[string]string
}

type Decoder struct{ /* unexported */ }

func NewDecoder() *Decoder
func (d *Decoder) Feed(p []byte) []Event
```

Its job is narrow (spec §7.5): find boundaries, extract fields. It never maintains a grid, never renders, never owns block layout.

- [ ] **Step 1: Write the vector test**

```go
package marks

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

type vector struct {
	Name   string `json:"name"`
	Input  string `json:"input"`
	Events []struct {
		Kind     string `json:"kind"`
		Tier     int    `json:"tier"`
		ExitCode *int   `json:"exitCode"`
		Path     string `json:"path"`
	} `json:"events"`
}

func TestEveryVectorDecodesToItsExpectedEvents(t *testing.T) {
	paths, err := filepath.Glob("../../protocol/vectors/*.json")
	if err != nil {
		t.Fatalf("glob vectors: %v", err)
	}
	if len(paths) < 16 {
		t.Fatalf("expected the full vector set, found %d", len(paths))
	}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		var v vector
		if err := json.Unmarshal(raw, &v); err != nil {
			t.Fatalf("parse %s: %v", path, err)
		}
		got := NewDecoder().Feed([]byte(v.Input))
		if len(got) != len(v.Events) {
			t.Fatalf("%s: got %d events, want %d", v.Name, len(got), len(v.Events))
		}
		for i, want := range v.Events {
			if got[i].Kind != want.Kind || int(got[i].Tier) != want.Tier {
				t.Errorf("%s event %d: got %+v, want %+v", v.Name, i, got[i], want)
			}
			if (got[i].ExitCode == nil) != (want.ExitCode == nil) {
				t.Errorf("%s event %d: exit code presence differs", v.Name, i)
			}
		}
	}
}

func TestMarkSplitAcrossFeedsStillDecodes(t *testing.T) {
	d := NewDecoder()
	if events := d.Feed([]byte("\x1b]133;")); len(events) != 0 {
		t.Fatalf("partial mark produced %d events", len(events))
	}
	events := d.Feed([]byte("A\x07"))
	if len(events) != 1 || events[0].Kind != "prompt_start" {
		t.Fatalf("got %+v", events)
	}
}

func TestUnterminatedOSCIsBounded(t *testing.T) {
	d := NewDecoder()
	d.Feed([]byte("\x1b]133;"))
	d.Feed(make([]byte, 256*1024))
	events := d.Feed([]byte("\x1b]133;A\x07"))
	if len(events) != 1 {
		t.Fatalf("decoder did not recover: %+v", events)
	}
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cd packages/terminal/go/marks && go test ./...`
Expected: FAIL — package does not compile.

- [ ] **Step 3: Implement the decoder**

Mirror `crates/marks` exactly, including the 4096-byte pending cap. The two implementations are independent code that MUST agree on every vector — that is the entire reason the vectors exist. Standard library only.

- [ ] **Step 4: Run the Go gates**

Run: `cd packages/terminal/go/marks && go test ./... && go vet ./...`
Expected: PASS.

- [ ] **Step 5: Confirm the boundary checker still passes**

Run: `npm --prefix packages/terminal run check:boundaries`
Expected: exit 0. `scripts/check-boundaries.mjs` already inspects `go.mod` replace directives for paths escaping the package; this module has none, and must not gain one.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/go
git commit -m "feat(terminal): add the Go mark decoder against the shared vectors"
```

---

### Task 7: Form blocks from marks inside `vt-core`

**Files:**
- Modify: `packages/terminal/crates/vt-core/src/parser.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Modify: `packages/terminal/crates/vt-core/src/grid.rs`
- Modify: `packages/terminal/crates/vt-core/Cargo.toml` (add `marks = { path = "../marks" }`)
- Create: `packages/terminal/crates/vt-core/src/alt_screen.rs`
- Test: `packages/terminal/crates/vt-core/tests/blocks_from_marks.rs`

**Interfaces:**
- Consumes `marks::{MarkDecoder, MarkEvent}` (Task 5) and `BlockGrid` (Task 3).
- Produces `TerminalCore::alt_screen_active(&self) -> bool`.
- Replaces the Task 1 stub in `build_snapshot` with the real `BlockGrid` projection.

- [ ] **Step 1: Write the integration tests**

Create `packages/terminal/crates/vt-core/tests/blocks_from_marks.rs`:

```rust
use vt_core::{BlockSource, BlockState, TerminalCore};

#[test]
fn osc133_alone_produces_correct_blocks_with_no_bootstrap() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07$ \x1b]133;B\x07ls\x1b]133;C\x07a.txt\nb.txt\n\x1b]133;D;0\x07");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].state, BlockState::Finished);
    assert_eq!(snapshot.blocks[0].source, BlockSource::Osc133);
    assert_eq!(snapshot.blocks[0].exit_code, Some(0));
}

#[test]
fn an_unpaired_prompt_start_abandons_the_open_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07one\n\x1b]133;A\x07two\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 2);
    assert_eq!(snapshot.blocks[0].state, BlockState::Abandoned);
    assert_eq!(snapshot.blocks[1].state, BlockState::Running);
}

#[test]
fn extension_marks_upgrade_the_block_and_carry_the_command() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07\x1b]7000;v=1;cmd=git%20status;cwd=%2Ftmp;branch=main\x07");
    core.feed(b"\x1b]133;C\x07clean\n\x1b]133;D;0\x07");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks[0].source, BlockSource::Extension);
    assert_eq!(snapshot.block_command(0), "git status");
    assert_eq!(snapshot.block_cwd(0), "/tmp");
    assert_eq!(snapshot.block_branch(0), "main");
}

#[test]
fn output_with_no_marks_lands_in_one_synthetic_block() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"no marks here\nat all\n");
    let snapshot = core.snapshot().unwrap();

    assert_eq!(snapshot.blocks.len(), 1);
    assert_eq!(snapshot.blocks[0].source, BlockSource::Synthetic);
}

#[test]
fn alt_screen_enter_and_leave_are_tracked() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    assert!(!core.alt_screen_active());
    core.feed(b"\x1b[?1049h");
    assert!(core.alt_screen_active());
    core.feed(b"\x1b[?1049l");
    assert!(!core.alt_screen_active());
}

#[test]
fn marks_inside_the_alt_screen_do_not_change_the_block_list() {
    let mut core = TerminalCore::new(40, 200).unwrap();
    core.feed(b"\x1b]133;A\x07\x1b]133;C\x07before\n");
    let before = core.snapshot().unwrap().blocks.len();

    core.feed(b"\x1b[?1049h");
    core.feed(b"\x1b]133;A\x07\x1b]133;A\x07\x1b]133;D;1\x07");
    assert_eq!(core.snapshot().unwrap().blocks.len(), before);

    core.feed(b"\x1b[?1049l");
    assert!(!core.alt_screen_active());
}

#[test]
fn blocks_survive_scrollback_trimming() {
    let mut core = TerminalCore::new(20, 10).unwrap();
    for index in 0..50 {
        core.feed(format!("\x1b]133;A\x07\x1b]133;C\x07row{index:03}\n\x1b]133;D;0\x07").as_bytes());
    }
    let snapshot = core.snapshot().unwrap();

    assert!(snapshot.blocks.len() <= 10);
    assert!(snapshot.blocks.iter().all(|b| b.row_count > 0));
    assert_eq!(snapshot.blocks.first().unwrap().first_row, 0);
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core --test blocks_from_marks`
Expected: FAIL — `alt_screen_active` does not exist and blocks are still the Task 1 stub.

- [ ] **Step 3: Route the byte stream through the decoder**

In `TerminalCore::feed`, run `MarkDecoder::feed` over the same bytes **before** `self.vte.advance`, then apply the resulting events to the `BlockGrid`.

Decoding independently of `vte` is deliberate: `vte` consumes OSC sequences into its own `osc_dispatch`, and threading our protocol through `Perform` would couple the block state machine to the parser's callback shape and make the split-read tests unreachable.

Event application:

| Event | Action |
| --- | --- |
| `PromptStart` | `grid.open_block(tier_source)` |
| `CommandStart` | note the command text start; no block change |
| `OutputStart` | note output start; no block change |
| `CommandEnd { exit_code }` | `grid.close_block(exit_code)` |
| `CwdChanged { path }` | `grid.set_meta_field("cwd", path)` |
| `Extension(fields)` | `grid.set_meta_field(k, v)` for each pair |
| `AltScreenEnter` / `AltScreenLeave` | `alt_screen.set(..)` |

While the alt screen is active, every event other than `AltScreenLeave` MUST be dropped before it reaches the grid. A full-screen TUI drawing something that looks like a mark cannot be allowed to shred the block list — that is what `marks_inside_the_alt_screen_do_not_change_the_block_list` pins.

`Parser::open_new_row` calls `grid.note_row_completed()`, and `Parser::trim_to` calls `grid.trim_to_first_row(dropped_row_count)` in the same pass that releases content, so the block indices and the row index can never drift.

- [ ] **Step 4: Replace the Task 1 stub**

In `build_snapshot`, replace the single-element `vec![BlockRecord { .. }]` with a projection over the `BlockGrid`, appending each block's `command`, `cwd` and `git_branch` into `block_text` and recording their `TextSpan`s. Every offset goes through `checked_u32`.

When the grid holds no blocks at all, emit the one `Synthetic` record covering every row — that is what keeps `output_with_no_marks_lands_in_one_synthetic_block` and every Phase 0 test passing unchanged.

- [ ] **Step 5: Run the whole workspace suite**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml --workspace`
Expected: PASS, including every Phase 0 test unchanged and the Task 1 contract tests.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal
git commit -m "feat(terminal): form blocks from marks and track the alt screen"
```

---

### Task 8: Selection in block coordinates

**Files:**
- Create: `packages/terminal/crates/vt-core/src/block_selection.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`

**Interfaces:**
- Produces `SelectionPoint { block: BlockId, row: usize, column: usize }` and `BlockSelection::{new, set_anchor, extend_to, normalized, is_empty, clear}`.

Reference: `crates/warp_terminal/src/model/selection.rs` (626 lines) for cross-block selection in block coordinates. Their renderer owns hit-testing; ours delegates to the browser, so we implement the model only.

- [ ] **Step 1: Write the tests**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn point(block: u64, row: usize, column: usize) -> SelectionPoint {
        SelectionPoint { block, row, column }
    }

    #[test]
    fn a_backwards_selection_normalizes_to_forwards() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(5, 2, 4));
        selection.extend_to(point(3, 0, 1));
        let (start, end) = selection.normalized().unwrap();
        assert_eq!(start, point(3, 0, 1));
        assert_eq!(end, point(5, 2, 4));
    }

    #[test]
    fn a_selection_within_one_block_normalizes_by_row_then_column() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 3, 9));
        selection.extend_to(point(1, 3, 2));
        let (start, end) = selection.normalized().unwrap();
        assert_eq!(start, point(1, 3, 2));
        assert_eq!(end, point(1, 3, 9));
    }

    #[test]
    fn an_anchor_with_no_extent_is_empty() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 0, 0));
        assert!(selection.is_empty());
        assert!(selection.normalized().is_none());
    }

    #[test]
    fn clear_discards_the_anchor() {
        let mut selection = BlockSelection::new();
        selection.set_anchor(point(1, 0, 0));
        selection.extend_to(point(2, 0, 0));
        selection.clear();
        assert!(selection.is_empty());
    }
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_selection`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement it**

Ordering is lexicographic on `(block, row, column)`. `BlockId` is monotonic and blocks are appended, so comparing ids orders blocks correctly without consulting the tree.

- [ ] **Step 4: Run the tests and commit**

```bash
cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core block_selection
git add packages/terminal/crates/vt-core
git commit -m "feat(terminal): add block-coordinate selection"
```

---

### Task 9: The incremental find engine

**Files:**
- Create: `packages/terminal/crates/vt-core/src/find.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Modify: `packages/terminal/crates/vt-core/Cargo.toml` (add `regex-automata = "0.4.6"`)
- Modify: `packages/terminal/Cargo.toml` (add it to `[workspace.dependencies]`)
- Test: `packages/terminal/crates/vt-core/tests/find.rs`

**Interfaces:**
- Produces `FindQuery::{literal, regex}`, `FindMatch { block: BlockId, row: usize, byte_range: Range<usize> }`, and `FindCursor::{step, results, is_complete, cancel}`.
- `TerminalCore::find(&self, query: FindQuery) -> FindCursor`.
- `FindCursor::step(&mut self, budget_blocks: usize)` searches at most `budget_blocks` blocks and returns, so the caller keeps the frame.

The UI is Phase 4. The engine ships now because it queries the sum tree built in Task 2, and retrofitting it later means rewriting the tree's cursor. Reference: `crates/warp_terminal/src/model/find.rs` (394) and `app/src/terminal/find/model/async_find.rs` (1,395) for the work-queue design.

- [ ] **Step 1: Write the tests**

Create `packages/terminal/crates/vt-core/tests/find.rs`:

```rust
use vt_core::{FindQuery, TerminalCore};

fn core_with_blocks(count: usize) -> TerminalCore {
    let mut core = TerminalCore::new(40, 10_000).unwrap();
    for index in 0..count {
        core.feed(
            format!("\x1b]133;A\x07\x1b]133;C\x07line {index} of text\n\x1b]133;D;0\x07").as_bytes(),
        );
    }
    core
}

#[test]
fn a_literal_query_finds_every_occurrence() {
    let core = core_with_blocks(20);
    let mut cursor = core.find(FindQuery::literal("line 7"));
    while !cursor.is_complete() {
        cursor.step(4);
    }
    assert_eq!(cursor.results().len(), 1);
}

#[test]
fn stepping_respects_the_budget_and_resumes_where_it_stopped() {
    let core = core_with_blocks(100);
    let mut cursor = core.find(FindQuery::literal("line"));
    cursor.step(10);
    assert!(!cursor.is_complete());
    let after_first = cursor.results().len();
    assert!(after_first > 0 && after_first < 100);

    while !cursor.is_complete() {
        cursor.step(10);
    }
    assert_eq!(cursor.results().len(), 100);
}

#[test]
fn a_cancelled_cursor_stops_producing_results() {
    let core = core_with_blocks(50);
    let mut cursor = core.find(FindQuery::literal("line"));
    cursor.step(5);
    let at_cancel = cursor.results().len();
    cursor.cancel();
    cursor.step(50);
    assert_eq!(cursor.results().len(), at_cancel);
    assert!(cursor.is_complete());
}

#[test]
fn an_invalid_regex_is_an_error_not_a_panic() {
    assert!(FindQuery::regex("(unclosed").is_err());
}

#[test]
fn a_valid_regex_matches_across_blocks() {
    let core = core_with_blocks(5);
    let mut cursor = core.find(FindQuery::regex(r"line \d of").unwrap());
    while !cursor.is_complete() {
        cursor.step(2);
    }
    assert_eq!(cursor.results().len(), 5);
}
```

- [ ] **Step 2: Run and confirm red**

Run: `cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core --test find`
Expected: FAIL — `find` does not exist.

- [ ] **Step 3: Implement it**

`FindQuery::literal` does substring search over each block's bytes. `FindQuery::regex` compiles a `regex_automata::meta::Regex` and returns `Err` on an invalid pattern rather than panicking — a user typing an unclosed group in a find box must not take the terminal down.

`FindCursor` holds the next block index and walks the sum tree forward, which is why the budget is expressed in blocks rather than rows or bytes. `cancel()` sets the cursor complete and freezes `results()`.

- [ ] **Step 4: Run, gate, commit**

```bash
cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core --test find
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
npm --prefix packages/terminal run check:boundaries
git add packages/terminal
git commit -m "feat(terminal): add the incremental find engine"
```

---

### Task 10: The additive-only zsh bootstrap

**Files:**
- Create: `packages/terminal/shell/zsh.sh`
- Create: `packages/terminal/shell/README.md`
- Create: `packages/terminal/ts/core/src/spawn-recipe.ts`
- Modify: `packages/terminal/ts/core/src/{types.ts,index.ts}`
- Test: `packages/terminal/shell/zsh.test.mjs`
- Test: `packages/terminal/ts/core/src/spawn-recipe.test.ts`

**Interfaces:**
- Produces `spawnRecipe(shell: "zsh", options: BootstrapOptions): SpawnRecipe`.
- `SpawnRecipe = { argv: string[]; env: Record<string, string> }`.
- `BootstrapOptions = { integration: "auto" | "osc133-only" | "off"; suppressPrompt: boolean }`.

**`suppressPrompt` MUST default to `false`, and Phase 1a MUST NOT pass `true` anywhere** (spec §8.1, §14.0, wrong turn 16).

- [ ] **Step 1: Write the shell behaviour test**

Create `packages/terminal/shell/zsh.test.mjs`. It runs a real zsh and asserts on the bytes it emits, skipping with a clear message when zsh is absent rather than failing.

```js
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import assert from "node:assert/strict";

const bootstrap = fileURLToPath(new URL("./zsh.sh", import.meta.url));
const haveZsh = (() => {
	try {
		execFileSync("zsh", ["--version"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
})();
const skip = haveZsh ? false : "zsh is not installed";

function runZsh(script) {
	return execFileSync("zsh", ["-f", "-c", script], { encoding: "latin1" });
}

test("emits prompt-start, command-end and one extension mark", { skip }, () => {
	const out = runZsh(
		`source ${bootstrap}; __operator_terminal_preexec 'echo hi'; __operator_terminal_precmd`,
	);
	assert.match(out, /\x1b\]133;A\x07/, "expected a prompt-start mark");
	assert.match(out, /\x1b\]133;D;/, "expected a command-end mark");
	assert.match(out, /\x1b\]7000;v=1;/, "expected one extension mark");
});

test("preserves the user's own precmd functions", { skip }, () => {
	const out = runZsh(
		"autoload -Uz add-zsh-hook; user_hook() { print -n USERHOOK }; " +
			`add-zsh-hook precmd user_hook; source ${bootstrap}; ` +
			"for f in $precmd_functions; do $f; done",
	);
	assert.match(out, /USERHOOK/, "the user's precmd hook must still run");
});

test("does not rebind any key", { skip }, () => {
	const before = runZsh("bindkey | sort");
	const after = runZsh(`source ${bootstrap}; bindkey | sort`);
	assert.equal(before, after, "bootstrap must not touch the keymap");
});

test("is idempotent under a second source", { skip }, () => {
	const out = runZsh(`source ${bootstrap}; source ${bootstrap}; __operator_terminal_precmd`);
	const marks = out.match(/\x1b\]133;A\x07/g) ?? [];
	assert.equal(marks.length, 1, "sourcing twice must not double-register the hook");
});

test("leaves the user's prompt alone", { skip }, () => {
	const out = runZsh(`PROMPT='MYPROMPT'; source ${bootstrap}; print -n $PROMPT`);
	assert.match(out, /MYPROMPT/, "Phase 1 must not suppress the user's prompt");
});
```

- [ ] **Step 2: Run and confirm red**

Run: `node --test packages/terminal/shell/zsh.test.mjs`
Expected: FAIL — `zsh.sh` does not exist.

- [ ] **Step 3: Write `zsh.sh`**

Under 200 lines. It MUST:

- return early on a guard variable it also sets, so a second source and any subshell are no-ops;
- `autoload -Uz add-zsh-hook`, then `add-zsh-hook precmd __operator_terminal_precmd` and `add-zsh-hook preexec __operator_terminal_preexec` — **append only**;
- emit `OSC 133 A` from precmd, `OSC 133 C` from preexec, and `OSC 133 D` carrying `$?` from the following precmd, capturing `$?` as the very first statement of precmd before anything else can clobber it;
- emit one `OSC 7000 v=1;id=..;cmd=..;cwd=..;branch=..;exit=..` alongside, percent-encoding every value with a pure-zsh encoder — no `printf %q`, no subprocess;
- read the branch from `git rev-parse --abbrev-ref HEAD` **only when the cwd is inside a work tree**, tolerating git being absent.

It MUST NOT: touch `precmd_functions` other than through `add-zsh-hook`; call `bindkey`; name any prompt framework; run any command for its own bookkeeping beyond the branch read; set `PROMPT` or `PS1` (Phase 2 owns that).

`shell/README.md` states that capability list and those refusals, and points at spec §8.

- [ ] **Step 4: Run the shell tests**

Run: `node --test packages/terminal/shell/zsh.test.mjs`
Expected: PASS (5 tests, or 5 skips on a machine without zsh).

- [ ] **Step 5: Write the `spawnRecipe` test**

Create `packages/terminal/ts/core/src/spawn-recipe.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { spawnRecipe } from "./index";

describe("spawnRecipe", () => {
	it("returns a bootstrap-sourcing recipe for auto integration", () => {
		const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: false });
		expect(recipe.argv[0]).toBe("zsh");
		expect(recipe.env.OPERATOR_TERMINAL_INTEGRATION).toBe("auto");
		expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("0");
	});

	it("returns a bare shell for osc133-only", () => {
		const recipe = spawnRecipe("zsh", { integration: "osc133-only", suppressPrompt: false });
		expect(recipe.argv).toEqual(["zsh"]);
		expect(recipe.env.OPERATOR_TERMINAL_INTEGRATION).toBe("osc133-only");
	});

	it("refuses to suppress the prompt in this phase", () => {
		expect(() => spawnRecipe("zsh", { integration: "auto", suppressPrompt: true })).toThrow(
			/prompt suppression is not available/i,
		);
	});
});
```

The third test is the guard that makes wrong turn 16 impossible to take by accident: the function throws until Phase 2 removes the guard deliberately.

- [ ] **Step 6: Implement `spawnRecipe` and run every gate**

```bash
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
node --test packages/terminal/shell/zsh.test.mjs
git add packages/terminal
git commit -m "feat(terminal): add the additive-only zsh bootstrap"
```

---

### Task 11: Close Phase 1a with the acceptance matrix

**Files:**
- Modify: `packages/terminal/CHANGELOG.md`
- Modify: `packages/terminal/README.md`
- Modify: `.github/workflows/terminal.yml`

- [ ] **Step 1: Add the Go and shell jobs to CI**

In `.github/workflows/terminal.yml`, in the `package` job after the existing `npm --prefix packages/terminal test` step:

```yaml
      - uses: actions/setup-go@v5
        with:
          go-version: "1.25.7"
      - run: cd packages/terminal/go/marks && go test ./... && go vet ./...
      - run: node --test packages/terminal/shell/zsh.test.mjs
```

`ubuntu-latest` ships zsh; if the runner image ever drops it the test skips rather than fails, which is why Task 10 Step 1 wrote it that way.

- [ ] **Step 2: Run the full matrix from a clean tree**

```bash
git clean -ndX packages/terminal
git clean -fdX packages/terminal
npm --prefix packages/terminal ci
npm --prefix packages/terminal run build:wasm
cargo fmt --manifest-path packages/terminal/Cargo.toml --all --check
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
cargo test --manifest-path packages/terminal/Cargo.toml --workspace --locked
node --test packages/terminal/scripts/check-boundaries.test.mjs packages/terminal/scripts/smoke-tauri.test.mjs
node --test packages/terminal/bench/schema.test.mjs packages/terminal/bench/workloads.test.mjs packages/terminal/bench/report-channel.test.mjs
node --test packages/terminal/shell/zsh.test.mjs
npm --prefix packages/terminal run check:boundaries
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
npm --prefix packages/terminal run smoke:vite
npm --prefix packages/terminal run smoke:tauri
npm run frontend:typecheck
npm run lint
```

Then, separately, because it changes directory:

```bash
cd packages/terminal/go/marks && go test ./... && go vet ./...
```

**Inspect the `git clean -ndX` output before running the `-fdX` form.** Stop if it names anything outside `node_modules/`, `target/`, `dist/`, `wasm/`, `fuzz/target/`, `fuzz/artifacts/` or `*.tsbuildinfo`.

Expected: every command exits 0.

- [ ] **Step 3: Prove the phase acceptance criteria**

Each is a test that exists by now. Confirm by name and record the result:

| Spec criterion | Proven by |
| --- | --- |
| OSC 133 alone, no bootstrap, produces correct blocks | `blocks_from_marks.rs::osc133_alone_produces_correct_blocks_with_no_bootstrap` |
| every §7.4 recovery row has a vector in both decoders | `marks/tests/vectors.rs` and `go/marks/marks_test.go`, 16 or more vectors each |
| fuzz clean including split-across-read marks | `cargo fuzz run decode -- -runs=200000` |
| blocks survive trimming | `blocks_from_marks.rs::blocks_survive_scrollback_trimming` |
| alt screen suspends block formation | `blocks_from_marks.rs::marks_inside_the_alt_screen_do_not_change_the_block_list` |
| the bootstrap is additive-only | `shell/zsh.test.mjs`, all five tests |
| prompt suppression is off | `spawn-recipe.test.ts::refuses to suppress the prompt in this phase` |

The remaining Phase 1 criteria — daemon capture with zero and with two clients attached, `vim` leaving one collapsed block, usable as the daily driver, the §9.4 perf gate, and 50,000 blocks at 60fps — belong to Phase 1b and **MUST NOT be claimed here**.

- [ ] **Step 4: Audit for Phase 2 leakage**

```bash
rg -n "input-ready|input-released|suppressPrompt: true|PS1=|PROMPT=" packages/terminal --glob '!*.md' --glob '!protocol/**'
```

Expected: matches only inside `spawn-recipe.ts`'s guard and its test. `input-ready` and `input-released` may appear in `protocol/SPEC.md` as reserved names and nowhere else.

- [ ] **Step 5: Update the changelog and commit**

Add a `## 0.2.0` section to `packages/terminal/CHANGELOG.md` covering: the block-aware core, the sum tree, the mark protocol with two decoders against shared vectors, the tolerant recovery table, the additive-only zsh bootstrap, block-coordinate selection, and the incremental find engine.

Record the deliberate O(n) renumbering in `BlockGrid::trim_to_first_row` (Task 3 Step 3) as a known cost with its reason, so a later reader does not mistake it for an oversight.

Update `README.md`'s capability statement: the core now forms blocks from OSC 133 and the `OSC 7000` extension, and does **not** own input.

```bash
git add packages/terminal .github/workflows/terminal.yml
git commit -m "chore(terminal): close phase 1a"
```

---

## Self-Review

**Spec coverage.** §6.3 blockgrid and sum tree — Tasks 2, 3. §6.4 selection — Task 8. §6.5 find — Task 9. §7.1 protocol location — Task 4. §7.2 two tiers — Tasks 4, 5, 7. §7.3 one encoding — Task 4 Step 1, Task 5 Step 5. §7.4 recovery table — Tasks 4, 5, 6, 7. §7.5 the Go decoder's narrow job — Task 6. §7.6 conformance and fuzzing — Tasks 4, 5. §8 additive-only bootstrap — Task 10. §8.1 suppression off — Task 10 Step 5's guard. §11 alt-screen tracked state — Task 7. §14.0 what 1a may not claim — Task 11 Step 3.

**Deferred to Phase 1b, deliberately:** `renderer-dom` virtualization, block headers, hover actions, alt-screen handoff to `XtermTerminal`, daemon capture via `tmux pipe-pane`, Operator wiring, and the §9.4 perf gate.

**Type consistency.** `BlockId` is `u64` in Rust and a `"high:low"` string in TypeScript; Task 1 Step 9 states why and `decodeBlocks` is the only place it is composed. `BlockRecord` is fourteen `u32` words (Task 1 Step 6) and `BLOCK_RECORD_WORDS` is exported from both sides. `BlockState` and `BlockSource` use the same ordinals in `block.rs`, in the export packing, and in `decodeBlocks`. `BlockGrid::open_block` takes only a `BlockSource` — the row it starts at comes from the grid's own row counter, not from the caller — and Tasks 3 and 7 agree on that signature.

**Known cost, accepted:** `BlockGrid::trim_to_first_row` renumbers every surviving block, which is O(n) per trim. Task 3 Step 3 states the reason and Task 11 Step 5 records it in the changelog.
