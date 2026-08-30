# Terminal Phase 4 — Completions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `packages/terminal` a completions engine — a declarative per-command
signature format, a cursor-location resolver, a smart-case fuzzy matcher, Warp's ranking
and Tab semantics, path/flag/subcommand providers, and a dropdown in the editor — without
ever executing anything in the user's shell.

**Architecture:** A new `ts/completions` workspace package holds the whole engine as pure
functions plus three providers. It never touches the DOM and never imports the editor. The
seam is a **provider interface registered on the core** (`ts/core`), because §10.1 forbids
`ts/editor` from importing `ts/completions`: the editor asks the core for completions and
renders whatever comes back. Filesystem access arrives through a new optional
`HostCapabilities.listDirectory`, so the package still knows nothing about Operator.

**Tech Stack:** TypeScript (ESM, `strict`), vitest 4.1.8, jsdom for the dropdown tests. No
new runtime dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §3.6 (no invisible execution), §4.1 (host boundary), §4.3 (enforcement), §9.4 (perf gate), §10.1 (dropdown lives in the editor, provider interface on the core), §14 Phase 4.

**Warp reference:** `/Users/omaraly/development/AI/warp`, read-only. §17.1 of the spec
governs how to cite it.

---

## Global Constraints

- **No comments in code.** The user's global `CLAUDE.md` rule. It applies to every file
  this plan creates. Explanations belong in this plan, in commit messages, and in
  `SPEC.md` — never in a `//` line.
- **No file over 600 lines.** Enforced in CI by `packages/terminal/scripts/check-boundaries.mjs`
  (`LINE_LIMIT = 600`), which covers `.ts`/`.tsx`/`.js`/`.mjs`/`.rs`/`.go`/`.sh`.
- **`ts/editor` MUST NOT import `ts/completions`; `ts/renderer-dom` MUST NOT import
  `ts/completions`.** Already encoded in `check-boundaries.mjs:141-146`. Do not weaken it.
- **The package MUST NOT import from `frontend/`, `backend/`, or `packages/shared/`.**
- **No completion path may execute anything in the user's shell.** §3.6 and Phase 4's
  first accept criterion. See Decision D1 — this is the one place this plan deliberately
  refuses to copy Warp.
- **User-facing copy goes through `TerminalStrings`.** The package ships English defaults
  and no locale files (§12.2).
- **Every task ends green.** `npm --prefix packages/terminal test` and
  `npm --prefix packages/terminal run check:boundaries` both pass before you commit.

---

## Verified against Warp's own implementation

Everything in this section was read in `/Users/omaraly/development/AI/warp` on 2026-08-30,
not recalled. The previous plan in this series shipped four unverified claims, one of which
would have destroyed scrollback, so the citations are load-bearing.

**Confirmed and copied:**

1. **The cursor resolves to a location, and each location has its own engine.**
   `LocationType::{Command, Flag, Argument, Variable}` at
   `crates/warp_completer/src/completer/engine/mod.rs:35-58`, with
   `mod {argument, command, flag, path, variable}` at `engine/mod.rs:1-11`. We copy the
   shape and defer `Variable` (D6).

2. **The signature format.** `CommandSignature { command: Command }` where
   `Command { name, alias, description, arguments, subcommands, options, priority }`,
   `Argument { name, description, values, optional, arity }`,
   `Opt { name: Vec<String>, description, arguments, required, priority }`,
   `Arity { limit, delimiter }`, `TemplateType::{Files, Folders, FilesAndFolders}` —
   `crates/warp_completer/src/signatures/v2/mod.rs:19-58, 194-208`.
   `Priority` is an `i32` clamped to `[-100, 100]` with `0` as the default
   (`v2/mod.rs:168-190`). `Opt::has_name` strips `--` then `-` before comparing
   (`v2/mod.rs:210-223`).

3. **The ranking order.** Exact → case-insensitive exact → prefix (input ordering
   preserved) → fuzzy by score descending. Stated as a doc comment at
   `crates/warp_completer/src/completer/suggest/mod.rs:311-315` and implemented as a
   `chain` at `suggest/mod.rs:405-416`. The match kinds are
   `Match::{Prefix, Exact, Fuzzy}` at `completer/matchers.rs:80-84`.

4. **Tab semantics.** `explicit_tab_completion` at `suggest/mod.rs:459-513`:
   no suggestions → `NoAction`; exactly one prefix suggestion → `InsertSingle`; else the
   longest common prefix over **case-sensitive** `Prefix`/`Exact` matches, if it is longer
   than the current replacement span and starts with the query → `InsertCommonPrefixAndOpen`;
   otherwise → `Open`. This is readline's behaviour and users have decades of muscle memory
   for it.

5. **Directory entries carry three facts.** `EngineDirEntry` exposes `file_name()`,
   `is_dir()` and `is_hidden()` — `completer/engine/path.rs:36-51`.

**Deliberate deviations, each with its reason:**

- **D1 — no generators, at all.** Warp's `ArgumentValue::Generator(GeneratorFn)` runs a
  shell script to produce suggestions: `GeneratorFn::ShellCommand { script, post_process }`
  where the script is "a sh command" (`signatures/v2/mod.rs:104-118`). These are exactly
  the "ongoing generator command jobs" that `zsh_body.sh:254-262` has to hunt down and kill
  in `warp_preexec`, which §3.6 cites as the thing we will not do. Our `ArgumentValue` union
  has **three** variants — `suggestion`, `template`, `root-command` — and no fourth. A
  future dynamic-values feature is a separate spec decision, not a quiet addition here.

- **D2 — the host lists directories, because the package cannot.** `HostCapabilities`
  (§4.1) has clipboard, links and notify, and no filesystem. A renderer in a browser has no
  `node:fs` and must not gain one. Phase 4 adds one optional method; a host that does not
  implement it gets every other provider and no path completions, which is a visible absence,
  not a silent degradation.

- **D3 — our own fuzzy scorer, not SkimMatcherV2.** Warp calls
  `SkimMatcherV2::default()` (smart-case) and `.ignore_case()` through its `fuzzy_match`
  crate (`crates/fuzzy_match/src/lib.rs:81-90, 128-136`). We cannot link a Rust matcher from
  a TypeScript package, and the `fuzzy-matcher` crate is not vendored into the Warp
  checkout, so its scoring constants could not be read and must not be invented as if they
  were. Task 3 implements an explicit scorer with named constants and pinned tests. We copy
  Warp's **smart-case rule** (a query containing any uppercase matches case-sensitively),
  which is observable behaviour, not an unverifiable constant.

- **D4 — `LocationType::Variable` is deferred.** Warp completes `$VAR`
  (`engine/variable.rs`, `engine/mod.rs:53-55`). Phase 4's deliverables in §14 list path,
  flag and git-subcommand providers and do not mention variables. Adding it is a Phase 5
  or later call; Task 2's `locate` returns `null` for a `$`-prefixed token so the behaviour
  is defined rather than accidental.

- **D5 — Tab is taken, and must be taken back.** `keymap.ts:69-70` currently maps `Tab` to
  `accept-suggestion`, which `line-editor.ts:192-197` uses to accept the ghost-text history
  suggestion. Warp uses Tab for completion and accepts ghost text with `→`. Task 10 rebinds:
  `Tab` → completions, `→` at end-of-line and `Ctrl-E` → accept ghost text. This changes
  existing tested behaviour and the existing tests must be repaired, not deleted.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `ts/completions/package.json` | Workspace manifest. Depends on `@operator/terminal-core` only. |
| `ts/completions/tsconfig.json` | Mirrors `ts/editor`'s, referencing `../core`. |
| `ts/completions/vitest.config.ts` | `environment: "node"` — nothing here touches the DOM. |
| `ts/completions/SPEC.md` | The documented schema for the signature format. Phase 4 accept criterion. |
| `ts/completions/src/signature.ts` | The declarative types, `clampPriority`, `optHasName`. |
| `ts/completions/src/registry.ts` | `SignatureRegistry` — lookup by name/alias, subcommand walk. |
| `ts/completions/src/parse.ts` | Tokenizer and `locate(line, cursor)` → `CompletionLocation`. |
| `ts/completions/src/match.ts` | `matchQuery` — exact, prefix, smart-case fuzzy with indices. |
| `ts/completions/src/rank.ts` | The four-tier ordering and `tabAction`. |
| `ts/completions/src/providers/path.ts` | Template-driven path completion over `listDirectory`. |
| `ts/completions/src/providers/flag.ts` | Options for the resolved command. |
| `ts/completions/src/providers/command.ts` | Top-level commands, subcommands, and literal argument values. |
| `ts/completions/src/specs/{git,cd,docker}.ts` | The three shipped command specs. |
| `ts/completions/src/specs/index.ts` | `defaultSignatures` — the array the registry loads. |
| `ts/completions/src/index.ts` | `createCompletionProvider(options)` and the public types. |
| `ts/core/src/completions.ts` | The provider contract, generation counter, cancellation. |
| `ts/core/src/terminal-core.ts` | Registration, `requestCompletions`, `onCompletions`, `currentCwd`. |
| `ts/core/src/types.ts` | `HostCapabilities.listDirectory?`, `DirEntry`. |
| `ts/editor/src/completions-dropdown.ts` | The dropdown element, selection state, keyboard. |
| `ts/editor/src/line-editor.ts` | Wires the dropdown to the core; Tab rebinding. |
| `ts/editor/src/keymap.ts` | `complete`, `accept-suggestion` on `→`/`Ctrl-E`. |

`match.ts` and `rank.ts` are separate because Warp separates them (`matchers.rs` vs
`suggest/mod.rs`) and because a scorer with pinned numeric expectations is reviewable on its
own. `providers/` is split three ways because each provider is independently rejectable.

---

### Task 1: The signature format and its registry

**Files:**
- Create: `packages/terminal/ts/completions/package.json`
- Create: `packages/terminal/ts/completions/tsconfig.json`
- Create: `packages/terminal/ts/completions/vitest.config.ts`
- Create: `packages/terminal/ts/completions/src/signature.ts`
- Create: `packages/terminal/ts/completions/src/registry.ts`
- Create: `packages/terminal/ts/completions/SPEC.md`
- Test: `packages/terminal/ts/completions/src/signature.test.ts`
- Test: `packages/terminal/ts/completions/src/registry.test.ts`
- Modify: `packages/terminal/package.json` — add `ts/completions` to `build:ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `CommandSpec`, `ArgumentSpec`, `OptSpec`, `ArgumentValue`, `Arity`,
  `SuggestionSpec`, `TemplateType`, `clampPriority(value: number): number`,
  `optHasName(opt: OptSpec, name: string): boolean`,
  `SignatureRegistry.from(specs: readonly CommandSpec[]): SignatureRegistry`,
  `registry.lookup(name: string): CommandSpec | null`,
  `registry.resolve(tokens: readonly string[]): ResolvedCommand | null` where
  `ResolvedCommand = { command: CommandSpec; consumed: number }`.

- [ ] **Step 1: Create the workspace package**

`packages/terminal/ts/completions/package.json`:

```json
{
	"name": "@operator/terminal-completions",
	"version": "0.1.0",
	"private": true,
	"type": "module",
	"description": "Completion engine for @operator/terminal-core.",
	"files": ["dist"],
	"main": "./dist/index.js",
	"types": "./dist/index.d.ts",
	"exports": {
		".": {
			"types": "./dist/index.d.ts",
			"import": "./dist/index.js"
		}
	},
	"scripts": {
		"build": "tsc -b",
		"test": "vitest run --config ./vitest.config.ts --passWithNoTests"
	},
	"dependencies": {
		"@operator/terminal-core": "file:../core"
	},
	"devDependencies": {
		"typescript": "5.9.3",
		"vitest": "4.1.8"
	}
}
```

`packages/terminal/ts/completions/tsconfig.json`:

```json
{
	"extends": "../../tsconfig.base.json",
	"compilerOptions": {
		"rootDir": "src",
		"outDir": "dist"
	},
	"include": ["src/**/*.ts"],
	"exclude": ["dist", "node_modules"],
	"references": [
		{ "path": "../core" }
	]
}
```

`packages/terminal/ts/completions/vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
	test: {
		environment: "node",
		include: ["src/**/*.test.ts"],
	},
});
```

In `packages/terminal/package.json`, change the `build:ts` script from
`"tsc -b ts/core ts/renderer-dom ts/editor ts/react"` to
`"tsc -b ts/core ts/renderer-dom ts/editor ts/completions ts/react"`.

Then run `npm --prefix packages/terminal install` so the workspace link is created.

- [ ] **Step 2: Write the failing tests**

`packages/terminal/ts/completions/src/signature.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { clampPriority, optHasName } from "./signature.js";

describe("clampPriority", () => {
	it("defaults to zero", () => {
		expect(clampPriority(undefined)).toBe(0);
	});

	it("clamps to Warp's [-100, 100] range", () => {
		expect(clampPriority(500)).toBe(100);
		expect(clampPriority(-500)).toBe(-100);
		expect(clampPriority(37)).toBe(37);
	});
});

describe("optHasName", () => {
	const opt = { name: ["-f", "--force"] };

	it("matches a long name without its hyphens", () => {
		expect(optHasName(opt, "force")).toBe(true);
	});

	it("matches a short name without its hyphen", () => {
		expect(optHasName(opt, "f")).toBe(true);
	});

	it("does not match a name that was never declared", () => {
		expect(optHasName(opt, "quiet")).toBe(false);
	});

	it("does not match when the caller leaves the hyphens on", () => {
		expect(optHasName(opt, "--force")).toBe(false);
	});
});
```

`packages/terminal/ts/completions/src/registry.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { SignatureRegistry } from "./registry.js";
import type { CommandSpec } from "./signature.js";

const git: CommandSpec = {
	name: "git",
	subcommands: [
		{ name: "commit", options: [{ name: ["-m", "--message"] }] },
		{ name: "checkout", alias: ["co"] },
		{
			name: "remote",
			subcommands: [{ name: "add" }, { name: "remove", alias: ["rm"] }],
		},
	],
};

const registry = SignatureRegistry.from([git, { name: "cd", alias: ["chdir"] }]);

describe("SignatureRegistry", () => {
	it("looks a command up by name", () => {
		expect(registry.lookup("git")?.name).toBe("git");
	});

	it("looks a command up by alias", () => {
		expect(registry.lookup("chdir")?.name).toBe("cd");
	});

	it("returns null for an unknown command", () => {
		expect(registry.lookup("kubectl")).toBeNull();
	});

	it("resolves a bare command, consuming one token", () => {
		expect(registry.resolve(["git"])).toEqual({ command: git, consumed: 1 });
	});

	it("descends into a subcommand", () => {
		const resolved = registry.resolve(["git", "commit"]);
		expect(resolved?.command.name).toBe("commit");
		expect(resolved?.consumed).toBe(2);
	});

	it("descends into a subcommand by alias", () => {
		const resolved = registry.resolve(["git", "co"]);
		expect(resolved?.command.name).toBe("checkout");
		expect(resolved?.consumed).toBe(2);
	});

	it("descends through nested subcommands", () => {
		const resolved = registry.resolve(["git", "remote", "rm"]);
		expect(resolved?.command.name).toBe("remove");
		expect(resolved?.consumed).toBe(3);
	});

	it("stops descending at a token that is not a subcommand", () => {
		const resolved = registry.resolve(["git", "commit", "-m", "wip"]);
		expect(resolved?.command.name).toBe("commit");
		expect(resolved?.consumed).toBe(2);
	});

	it("returns null when the first token is unknown", () => {
		expect(registry.resolve(["kubectl", "get"])).toBeNull();
	});

	it("returns null for no tokens", () => {
		expect(registry.resolve([])).toBeNull();
	});
});
```

- [ ] **Step 3: Run the tests and watch them fail**

```bash
npm --prefix packages/terminal/ts/completions test
```

Expected: FAIL — `Failed to resolve import "./signature.js"`.

- [ ] **Step 4: Write `signature.ts`**

```ts
export type TemplateType = "files" | "folders" | "files-and-folders";

export type SuggestionSpec = Readonly<{
	value: string;
	displayValue?: string;
	description?: string;
	priority?: number;
}>;

export type ArgumentValue =
	| Readonly<{ kind: "suggestion"; suggestion: SuggestionSpec }>
	| Readonly<{ kind: "template"; template: TemplateType }>
	| Readonly<{ kind: "root-command" }>;

export type Arity = Readonly<{ limit?: number; delimiter?: string }>;

export type ArgumentSpec = Readonly<{
	name: string;
	description?: string;
	values?: readonly ArgumentValue[];
	optional?: boolean;
	arity?: Arity;
}>;

export type OptSpec = Readonly<{
	name: readonly string[];
	description?: string;
	arguments?: readonly ArgumentSpec[];
	required?: boolean;
	priority?: number;
}>;

export type CommandSpec = Readonly<{
	name: string;
	alias?: readonly string[];
	description?: string;
	arguments?: readonly ArgumentSpec[];
	subcommands?: readonly CommandSpec[];
	options?: readonly OptSpec[];
	priority?: number;
}>;

export const MIN_PRIORITY = -100;
export const MAX_PRIORITY = 100;
export const DEFAULT_PRIORITY = 0;

export function clampPriority(value: number | undefined): number {
	if (value === undefined || !Number.isFinite(value)) return DEFAULT_PRIORITY;
	return Math.min(MAX_PRIORITY, Math.max(MIN_PRIORITY, Math.trunc(value)));
}

export function optHasName(opt: Pick<OptSpec, "name">, name: string): boolean {
	return opt.name.some((declared) => {
		if (declared.startsWith("--")) return declared.slice(2) === name;
		if (declared.startsWith("-")) return declared.slice(1) === name;
		return false;
	});
}

export function isVariadic(argument: ArgumentSpec): boolean {
	return argument.arity !== undefined && argument.arity.limit === undefined;
}
```

- [ ] **Step 5: Write `registry.ts`**

```ts
import type { CommandSpec } from "./signature.js";

export type ResolvedCommand = Readonly<{ command: CommandSpec; consumed: number }>;

export class SignatureRegistry {
	private readonly byName: ReadonlyMap<string, CommandSpec>;
	private readonly roots: readonly CommandSpec[];

	private constructor(byName: ReadonlyMap<string, CommandSpec>, roots: readonly CommandSpec[]) {
		this.byName = byName;
		this.roots = roots;
	}

	static from(specs: readonly CommandSpec[]): SignatureRegistry {
		const byName = new Map<string, CommandSpec>();
		for (const spec of specs) {
			byName.set(spec.name, spec);
			for (const alias of spec.alias ?? []) byName.set(alias, spec);
		}
		return new SignatureRegistry(byName, specs);
	}

	commands(): readonly CommandSpec[] {
		return this.roots;
	}

	lookup(name: string): CommandSpec | null {
		return this.byName.get(name) ?? null;
	}

	resolve(tokens: readonly string[]): ResolvedCommand | null {
		const first = tokens[0];
		if (first === undefined) return null;
		let command = this.lookup(first);
		if (command === null) return null;
		let consumed = 1;
		while (consumed < tokens.length) {
			const next = matchSubcommand(command, tokens[consumed]!);
			if (next === null) break;
			command = next;
			consumed += 1;
		}
		return { command, consumed };
	}
}

function matchSubcommand(command: CommandSpec, token: string): CommandSpec | null {
	for (const sub of command.subcommands ?? []) {
		if (sub.name === token) return sub;
		if ((sub.alias ?? []).includes(token)) return sub;
	}
	return null;
}
```

- [ ] **Step 6: Run the tests and watch them pass**

```bash
npm --prefix packages/terminal/ts/completions test
```

Expected: PASS, 15 tests.

- [ ] **Step 7: Write `SPEC.md`**

This is a Phase 4 accept criterion ("a documented schema"), so it must be a real reference,
not a pointer. Write `packages/terminal/ts/completions/SPEC.md` covering:

- one worked example — the full `git commit` spec from `registry.test.ts` — shown as
  TypeScript, since specs are TypeScript modules, not JSON;
- a field table for `CommandSpec`, `ArgumentSpec`, `OptSpec`, `Arity`, `SuggestionSpec`,
  giving each field's type, whether it is optional, and its default;
- the three `ArgumentValue` kinds, with one example each;
- the priority rule stated as: an integer clamped to `[-100, 100]`, default `0`, higher
  sorts first within a match tier, ties broken by display text ascending;
- a section headed **"Why there is no generator"** stating that Warp's fourth
  `ArgumentValue` variant runs a shell script (`signatures/v2/mod.rs:104-118`), that §3.6
  forbids it, and that a dynamic-values feature needs a spec decision before it is added.

- [ ] **Step 8: Verify the boundary and line checks pass**

```bash
npm --prefix packages/terminal run check:boundaries
```

Expected: exit 0. The script already knows `@operator/terminal-completions`
(`check-boundaries.mjs:39, 120-121`), so no change to it is needed here.

- [ ] **Step 9: Commit**

```bash
git add packages/terminal/ts/completions packages/terminal/package.json packages/terminal/package-lock.json
git commit -m "feat(terminal): add the completion signature format and its registry"
```

---

### Task 2: Locating the cursor in a command line

**Files:**
- Create: `packages/terminal/ts/completions/src/parse.ts`
- Test: `packages/terminal/ts/completions/src/parse.test.ts`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `Span = { start: number; end: number }`,
  `CompletionLocation` (the tagged union below),
  `locate(line: string, cursor: number): CompletionLocation | null`,
  `tokenize(line: string): Token[]` where `Token = { text: string; span: Span }`.

`locate` returns the *shape* of the completion, not its contents — no registry, no
filesystem. That is what makes it a pure function with cheap tests, and it mirrors Warp's
`Flatten` producing a `CompletionLocation` before any engine runs
(`completer/engine/mod.rs:31, 66-80`).

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/parse.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { locate, tokenize } from "./parse.js";

describe("tokenize", () => {
	it("splits on whitespace and records spans", () => {
		expect(tokenize("git commit")).toEqual([
			{ text: "git", span: { start: 0, end: 3 } },
			{ text: "commit", span: { start: 4, end: 10 } },
		]);
	});

	it("keeps a double-quoted run as one token", () => {
		expect(tokenize('git commit -m "a b"')).toEqual([
			{ text: "git", span: { start: 0, end: 3 } },
			{ text: "commit", span: { start: 4, end: 10 } },
			{ text: "-m", span: { start: 11, end: 13 } },
			{ text: "a b", span: { start: 14, end: 19 } },
		]);
	});

	it("keeps a single-quoted run as one token", () => {
		expect(tokenize("echo 'x y'")).toEqual([
			{ text: "echo", span: { start: 0, end: 4 } },
			{ text: "x y", span: { start: 5, end: 10 } },
		]);
	});

	it("returns nothing for a blank line", () => {
		expect(tokenize("   ")).toEqual([]);
	});
});

describe("locate", () => {
	it("locates a command being typed", () => {
		expect(locate("gi", 2)).toEqual({
			kind: "command",
			query: "gi",
			span: { start: 0, end: 2 },
			commandTokens: [],
		});
	});

	it("locates an empty command on an empty line", () => {
		expect(locate("", 0)).toEqual({
			kind: "command",
			query: "",
			span: { start: 0, end: 0 },
			commandTokens: [],
		});
	});

	it("locates an argument after a trailing space", () => {
		expect(locate("git ", 4)).toEqual({
			kind: "argument",
			query: "",
			span: { start: 4, end: 4 },
			commandTokens: ["git"],
		});
	});

	it("locates a partially typed argument", () => {
		expect(locate("git comm", 8)).toEqual({
			kind: "argument",
			query: "comm",
			span: { start: 4, end: 8 },
			commandTokens: ["git"],
		});
	});

	it("locates a flag by its leading hyphen", () => {
		expect(locate("git commit --me", 15)).toEqual({
			kind: "flag",
			query: "--me",
			span: { start: 11, end: 15 },
			commandTokens: ["git", "commit"],
		});
	});

	it("locates a bare hyphen as a flag", () => {
		expect(locate("ls -", 4)).toEqual({
			kind: "flag",
			query: "-",
			span: { start: 3, end: 4 },
			commandTokens: ["ls"],
		});
	});

	it("locates the token the cursor sits inside, not the last one", () => {
		expect(locate("git commit -m", 7)).toEqual({
			kind: "argument",
			query: "com",
			span: { start: 4, end: 10 },
			commandTokens: ["git"],
		});
	});

	it("declines a variable, which is deferred", () => {
		expect(locate("echo $HO", 8)).toBeNull();
	});

	it("declines a cursor inside leading whitespace", () => {
		expect(locate("  git", 1)).toBeNull();
	});
});
```

Note the eighth case: `"git commit -m"` has `commit` spanning offsets 4–10, so with the
cursor at offset 7 the query is `"com"` — the text from the token start to the cursor —
while the span still covers the whole token. Warp does the same: `Span` is what gets
replaced, the query is what was typed so far. Getting this backwards makes mid-token
completion delete the tail silently.

The last case is the one that needs the guard in Step 3: at offset 1 of `"  git"` the
cursor is in leading whitespace with a token still ahead of it, and completing there would
insert *before* `git` rather than replacing it.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- parse
```

Expected: FAIL — `Failed to resolve import "./parse.js"`.

- [ ] **Step 3: Write `parse.ts`**

```ts
export type Span = Readonly<{ start: number; end: number }>;

export type Token = Readonly<{ text: string; span: Span }>;

export type CompletionLocation = Readonly<{
	kind: "command" | "flag" | "argument";
	query: string;
	span: Span;
	commandTokens: readonly string[];
}>;

export function tokenize(line: string): Token[] {
	const tokens: Token[] = [];
	let index = 0;
	while (index < line.length) {
		while (index < line.length && line[index] === " ") index += 1;
		if (index >= line.length) break;
		const start = index;
		let text = "";
		let quote: string | null = null;
		while (index < line.length) {
			const ch = line[index]!;
			if (quote !== null) {
				if (ch === quote) quote = null;
				else text += ch;
			} else if (ch === '"' || ch === "'") {
				quote = ch;
			} else if (ch === " ") {
				break;
			} else {
				text += ch;
			}
			index += 1;
		}
		tokens.push({ text, span: { start, end: index } });
	}
	return tokens;
}

export function locate(line: string, cursor: number): CompletionLocation | null {
	const clamped = Math.min(Math.max(cursor, 0), line.length);
	const tokens = tokenize(line);
	const index = tokens.findIndex(
		(token) => clamped >= token.span.start && clamped <= token.span.end,
	);

	if (index === -1) {
		if (clamped > 0 && line[clamped - 1] !== " ") return null;
		if (tokens.some((token) => token.span.start >= clamped)) return null;
		const commandTokens = tokens
			.filter((token) => token.span.end < clamped)
			.map((token) => token.text);
		const span = { start: clamped, end: clamped };
		if (commandTokens.length === 0) {
			return { kind: "command", query: "", span, commandTokens: [] };
		}
		return { kind: "argument", query: "", span, commandTokens };
	}

	const token = tokens[index]!;
	const query = line.slice(token.span.start, clamped);
	if (query.startsWith("$")) return null;
	const commandTokens = tokens.slice(0, index).map((entry) => entry.text);
	if (index === 0) {
		return { kind: "command", query, span: token.span, commandTokens: [] };
	}
	const kind = query.startsWith("-") ? "flag" : "argument";
	return { kind, query, span: token.span, commandTokens };
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test -- parse
```

Expected: PASS, 14 tests.

- [ ] **Step 5: Sabotage the implementation to prove the tests bite**

Temporarily change `const query = line.slice(token.span.start, clamped);` to
`const query = token.text;` and re-run. Expected: the "locates the token the cursor sits
inside" test FAILS with `"commit"` where `"co"` was expected. Revert the sabotage and
confirm green again. Do not commit the sabotage.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/ts/completions/src/parse.ts packages/terminal/ts/completions/src/parse.test.ts
git commit -m "feat(terminal): resolve a cursor position to a completion location"
```

---

### Task 3: The matcher — exact, prefix, and smart-case fuzzy

**Files:**
- Create: `packages/terminal/ts/completions/src/match.ts`
- Test: `packages/terminal/ts/completions/src/match.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `MatchResult` (union below) and
  `matchQuery(text: string, query: string): MatchResult | null`.

Read D3 before starting. This scorer is **ours**; do not claim in a commit message or a
comment that it reproduces SkimMatcherV2. What we copy from Warp is the smart-case rule.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/match.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { matchQuery } from "./match.js";

describe("matchQuery", () => {
	it("treats an empty query as a prefix match of everything", () => {
		expect(matchQuery("anything", "")).toEqual({ kind: "prefix", caseSensitive: true });
	});

	it("reports an exact match", () => {
		expect(matchQuery("commit", "commit")).toEqual({ kind: "exact", caseSensitive: true });
	});

	it("reports a case-insensitive exact match", () => {
		expect(matchQuery("Commit", "commit")).toEqual({ kind: "exact", caseSensitive: false });
	});

	it("reports a prefix match", () => {
		expect(matchQuery("commit", "com")).toEqual({ kind: "prefix", caseSensitive: true });
	});

	it("reports a case-insensitive prefix match", () => {
		expect(matchQuery("Commit", "com")).toEqual({ kind: "prefix", caseSensitive: false });
	});

	it("falls through to fuzzy when the query is scattered", () => {
		const result = matchQuery("commit", "cmt");
		expect(result?.kind).toBe("fuzzy");
	});

	it("returns the matched indices so the UI can highlight them", () => {
		const result = matchQuery("commit", "cmt");
		expect(result).toMatchObject({ kind: "fuzzy", indices: [0, 2, 5] });
	});

	it("returns null when the query is not a subsequence", () => {
		expect(matchQuery("commit", "xyz")).toBeNull();
	});

	it("is case-insensitive while the query is all lowercase", () => {
		expect(matchQuery("README", "readme")).toEqual({ kind: "exact", caseSensitive: false });
	});

	it("becomes case-sensitive as soon as the query has an uppercase letter", () => {
		expect(matchQuery("readme", "README")).toBeNull();
		expect(matchQuery("README", "README")).toEqual({ kind: "exact", caseSensitive: true });
	});

	it("scores a word-start match above a mid-word one", () => {
		const wordStart = matchQuery("git-commit", "gc");
		const midWord = matchQuery("gxxcxx", "gc");
		expect(wordStart?.kind).toBe("fuzzy");
		expect(midWord?.kind).toBe("fuzzy");
		expect((wordStart as { score: number }).score).toBeGreaterThan(
			(midWord as { score: number }).score,
		);
	});

	it("scores consecutive characters above scattered ones", () => {
		const consecutive = matchQuery("xxcommit", "com");
		const scattered = matchQuery("xxcxoxm", "com");
		expect((consecutive as { score: number }).score).toBeGreaterThan(
			(scattered as { score: number }).score,
		);
	});

	it("scores a camelCase boundary as a word start", () => {
		const camel = matchQuery("gitCommit", "gC");
		expect(camel?.kind).toBe("fuzzy");
		expect((camel as { score: number }).score).toBeGreaterThan(0);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- match
```

Expected: FAIL — `Failed to resolve import "./match.js"`.

- [ ] **Step 3: Write `match.ts`**

```ts
export type MatchResult =
	| Readonly<{ kind: "exact"; caseSensitive: boolean }>
	| Readonly<{ kind: "prefix"; caseSensitive: boolean }>
	| Readonly<{ kind: "fuzzy"; score: number; indices: readonly number[] }>;

export const BONUS_FIRST_CHAR = 24;
export const BONUS_WORD_START = 16;
export const BONUS_CONSECUTIVE = 8;
export const PENALTY_GAP = 3;
export const MAX_GAP_PENALTY = 12;

const WORD_SEPARATORS = new Set(["/", "-", "_", ".", " ", ":", "@"]);

export function matchQuery(text: string, query: string): MatchResult | null {
	if (query.length === 0) return { kind: "prefix", caseSensitive: true };

	const caseSensitive = /[A-Z]/.test(query);
	const haystack = caseSensitive ? text : text.toLowerCase();
	const needle = caseSensitive ? query : query.toLowerCase();

	if (haystack === needle) return { kind: "exact", caseSensitive: text === query };
	if (haystack.startsWith(needle)) {
		return { kind: "prefix", caseSensitive: text.startsWith(query) };
	}

	const indices = subsequenceIndices(haystack, needle);
	if (indices === null) return null;
	return { kind: "fuzzy", score: scoreIndices(text, indices), indices };
}

function subsequenceIndices(haystack: string, needle: string): number[] | null {
	const indices: number[] = [];
	let position = 0;
	for (const ch of needle) {
		const found = haystack.indexOf(ch, position);
		if (found === -1) return null;
		indices.push(found);
		position = found + 1;
	}
	return indices;
}

function scoreIndices(text: string, indices: readonly number[]): number {
	let score = 0;
	let previous = -1;
	for (const index of indices) {
		if (index === 0) score += BONUS_FIRST_CHAR;
		else if (isWordStart(text, index)) score += BONUS_WORD_START;
		if (previous >= 0) {
			if (index === previous + 1) score += BONUS_CONSECUTIVE;
			else score -= Math.min(MAX_GAP_PENALTY, (index - previous - 1) * PENALTY_GAP);
		}
		previous = index;
	}
	return score;
}

function isWordStart(text: string, index: number): boolean {
	const previous = text[index - 1];
	if (previous === undefined) return true;
	if (WORD_SEPARATORS.has(previous)) return true;
	const current = text[index]!;
	return previous === previous.toLowerCase() && current === current.toUpperCase()
		&& current !== current.toLowerCase();
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test -- match
```

Expected: PASS, 13 tests.

- [ ] **Step 5: Document the constants in SPEC.md**

Append a **"Fuzzy scoring"** section to `packages/terminal/ts/completions/SPEC.md` listing
the five exported constants with their values and the rule each encodes, plus one sentence
recording that Warp uses `SkimMatcherV2` (`crates/fuzzy_match/src/lib.rs:81-83`) and that
this is a behavioural equivalent, not a port. A future tuning change must update this table.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/ts/completions/src/match.ts packages/terminal/ts/completions/src/match.test.ts packages/terminal/ts/completions/SPEC.md
git commit -m "feat(terminal): match completions by exact, prefix and smart-case fuzzy"
```

---

### Task 4: Ranking, and Warp's Tab semantics

**Files:**
- Create: `packages/terminal/ts/completions/src/rank.ts`
- Test: `packages/terminal/ts/completions/src/rank.test.ts`

**Interfaces:**
- Consumes: `MatchResult`, `matchQuery` (Task 3); `Span` (Task 2).
- Produces:
  `Candidate = { value: string; displayValue?: string; description?: string; priority?: number; kind: CandidateKind }`,
  `CandidateKind = "command" | "subcommand" | "flag" | "argument" | "path"`,
  `Ranked = { candidate: Candidate; match: MatchResult }`,
  `rank(candidates: readonly Candidate[], query: string): Ranked[]`,
  `TabAction` (union below),
  `tabAction(ranked: readonly Ranked[], query: string, span: Span): TabAction`.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/rank.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { rank, tabAction } from "./rank.js";
import type { Candidate } from "./rank.js";

const candidate = (value: string, priority?: number): Candidate => ({
	value,
	kind: "subcommand",
	priority,
});

const values = (input: readonly { candidate: Candidate }[]): string[] =>
	input.map((entry) => entry.candidate.value);

describe("rank", () => {
	it("puts an exact match first, ahead of a shorter prefix match", () => {
		const ranked = rank([candidate("commitment"), candidate("commit")], "commit");
		expect(values(ranked)).toEqual(["commit", "commitment"]);
	});

	it("puts a case-sensitive exact match ahead of a case-insensitive one", () => {
		const ranked = rank([candidate("Readme"), candidate("readme")], "readme");
		expect(values(ranked)).toEqual(["readme", "Readme"]);
	});

	it("puts every prefix match ahead of every fuzzy match", () => {
		const ranked = rank([candidate("c-m-x"), candidate("cmt")], "cm");
		expect(values(ranked)).toEqual(["cmt", "c-m-x"]);
	});

	it("orders prefix matches by priority descending", () => {
		const ranked = rank(
			[candidate("commit", 0), candidate("checkout", 50), candidate("cherry-pick", 10)],
			"c",
		);
		expect(values(ranked)).toEqual(["checkout", "cherry-pick", "commit"]);
	});

	it("breaks a priority tie by display text ascending", () => {
		const ranked = rank([candidate("cz", 5), candidate("ca", 5)], "c");
		expect(values(ranked)).toEqual(["ca", "cz"]);
	});

	it("orders fuzzy matches by score descending", () => {
		const ranked = rank([candidate("xxcxxxoxxxm"), candidate("x-com")], "com");
		expect(values(ranked)).toEqual(["x-com", "xxcxxxoxxxm"]);
	});

	it("drops candidates that do not match at all", () => {
		const ranked = rank([candidate("commit"), candidate("push")], "com");
		expect(values(ranked)).toEqual(["commit"]);
	});

	it("returns everything, priority-ordered, for an empty query", () => {
		const ranked = rank([candidate("b", 0), candidate("a", 90)], "");
		expect(values(ranked)).toEqual(["a", "b"]);
	});
});

describe("tabAction", () => {
	const span = { start: 4, end: 6 };

	it("does nothing when there is nothing to complete", () => {
		expect(tabAction([], "co", span)).toEqual({ kind: "none" });
	});

	it("inserts outright when exactly one candidate matches by prefix", () => {
		const ranked = rank([candidate("commit"), candidate("push")], "co");
		expect(tabAction(ranked, "co", span)).toEqual({
			kind: "insert",
			text: "commit",
			span,
		});
	});

	it("inserts the longest common prefix and opens when several share one", () => {
		const ranked = rank([candidate("commit"), candidate("commit-tree")], "co");
		const action = tabAction(ranked, "co", span);
		expect(action).toMatchObject({ kind: "insert-and-open", text: "commit", span });
	});

	it("opens without inserting when the common prefix adds nothing", () => {
		const ranked = rank([candidate("commit"), candidate("checkout")], "c");
		expect(tabAction(ranked, "c", { start: 4, end: 5 })).toMatchObject({ kind: "open" });
	});

	it("ignores case-insensitive matches when computing the common prefix", () => {
		const ranked = rank([candidate("Commit-tree"), candidate("commit-message")], "commit");
		const action = tabAction(ranked, "commit", { start: 4, end: 10 });
		expect(action).toMatchObject({ kind: "insert-and-open", text: "commit-message" });
	});
});
```

The last case is the subtle one and it is Warp's rule, not an invention:
`explicit_tab_completion` filters the common-prefix computation to
`Match::Prefix { is_case_sensitive: true } | Match::Exact { is_case_sensitive: true }`
(`suggest/mod.rs:481-492`). Both candidates here match `commit` by prefix, so the
single-prefix shortcut does not fire; without the case filter the common prefix of
`Commit-tree` and `commit-message` is empty and Tab would do nothing, when it should
insert `commit-message`.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- rank
```

Expected: FAIL — `Failed to resolve import "./rank.js"`.

- [ ] **Step 3: Write `rank.ts`**

```ts
import { matchQuery, type MatchResult } from "./match.js";
import { clampPriority } from "./signature.js";
import type { Span } from "./parse.js";

export type CandidateKind = "command" | "subcommand" | "flag" | "argument" | "path";

export type Candidate = Readonly<{
	value: string;
	displayValue?: string;
	description?: string;
	priority?: number;
	kind: CandidateKind;
	isDirectory?: boolean;
}>;

export type Ranked = Readonly<{ candidate: Candidate; match: MatchResult }>;

export type TabAction =
	| Readonly<{ kind: "none" }>
	| Readonly<{ kind: "insert"; text: string; span: Span }>
	| Readonly<{ kind: "insert-and-open"; text: string; span: Span; results: readonly Ranked[] }>
	| Readonly<{ kind: "open"; results: readonly Ranked[] }>;

const display = (candidate: Candidate): string => candidate.displayValue ?? candidate.value;

export function rank(candidates: readonly Candidate[], query: string): Ranked[] {
	const ordered = [...candidates].sort((left, right) => {
		const byPriority = clampPriority(right.priority) - clampPriority(left.priority);
		if (byPriority !== 0) return byPriority;
		return display(left).localeCompare(display(right));
	});

	const exact: Ranked[] = [];
	const exactInsensitive: Ranked[] = [];
	const prefix: Ranked[] = [];
	const fuzzy: Ranked[] = [];

	for (const candidate of ordered) {
		const match = matchQuery(display(candidate), query);
		if (match === null) continue;
		const entry = { candidate, match };
		if (match.kind === "exact") (match.caseSensitive ? exact : exactInsensitive).push(entry);
		else if (match.kind === "prefix") prefix.push(entry);
		else fuzzy.push(entry);
	}

	fuzzy.sort((left, right) => {
		const leftScore = left.match.kind === "fuzzy" ? left.match.score : 0;
		const rightScore = right.match.kind === "fuzzy" ? right.match.score : 0;
		return rightScore - leftScore;
	});

	return [...exact, ...exactInsensitive, ...prefix, ...fuzzy];
}

export function tabAction(ranked: readonly Ranked[], query: string, span: Span): TabAction {
	if (ranked.length === 0) return { kind: "none" };

	const prefixMatches = ranked.filter((entry) => entry.match.kind === "prefix");
	if (prefixMatches.length === 1) {
		return { kind: "insert", text: prefixMatches[0]!.candidate.value, span };
	}

	const caseSensitive = ranked.filter(
		(entry) =>
			(entry.match.kind === "prefix" || entry.match.kind === "exact") &&
			entry.match.caseSensitive,
	);
	const common = longestCommonPrefix(caseSensitive.map((entry) => entry.candidate.value));
	if (common !== null && common.length > query.length && common.startsWith(query)) {
		return { kind: "insert-and-open", text: common, span, results: ranked };
	}

	return { kind: "open", results: ranked };
}

function longestCommonPrefix(values: readonly string[]): string | null {
	const first = values[0];
	if (first === undefined) return null;
	let prefix = first;
	for (const value of values.slice(1)) {
		let length = 0;
		while (length < prefix.length && length < value.length && prefix[length] === value[length]) {
			length += 1;
		}
		prefix = prefix.slice(0, length);
		if (prefix.length === 0) return null;
	}
	return prefix;
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test -- rank
```

Expected: PASS, 13 tests.

- [ ] **Step 5: Sabotage to prove the case-sensitivity filter is tested**

Temporarily drop `&& entry.match.caseSensitive` from the `caseSensitive` filter in
`tabAction` and re-run. Expected: "ignores case-insensitive matches when computing the
common prefix" FAILS. Revert and confirm green.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/ts/completions/src/rank.ts packages/terminal/ts/completions/src/rank.test.ts
git commit -m "feat(terminal): rank completions and give Tab Warp's semantics"
```

---

### Task 5: The provider seam on the core

**Files:**
- Create: `packages/terminal/ts/core/src/completions.ts`
- Modify: `packages/terminal/ts/core/src/types.ts` — `DirEntry`, `HostCapabilities.listDirectory?`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts` — registration, request, listeners, `currentCwd`
- Modify: `packages/terminal/ts/core/src/index.ts` — export the new types
- Test: `packages/terminal/ts/core/src/completions.test.ts`

**Interfaces:**
- Consumes: nothing from `ts/completions` — the core must not depend on it. This direction
  is what keeps §10.1 satisfiable.
- Produces:
  `DirEntry = { name: string; isDirectory: boolean; isHidden: boolean }`;
  `HostCapabilities.listDirectory?(path: string): Promise<readonly DirEntry[]>`;
  `CompletionItem = { value: string; displayValue: string; description: string | null; kind: string; matchedIndices: readonly number[] }`;
  `CompletionResult = { items: readonly CompletionItem[]; span: { start: number; end: number }; query: string }`;
  `CompletionRequest = { line: string; cursor: number; cwd: string; host: HostCapabilities; signal: AbortSignal }`;
  `CompletionProvider = (request: CompletionRequest) => Promise<CompletionResult | null>`;
  on `TerminalCore`: `registerCompletionProvider(provider): () => void`,
  `requestCompletions(line: string, cursor: number): void`,
  `cancelCompletions(): void`,
  `onCompletions(listener: (result: CompletionResult | null) => void): () => void`,
  `currentCwd(): string`.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/core/src/completions.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { CompletionDispatcher } from "./completions.js";
import type { CompletionRequest, CompletionResult } from "./completions.js";

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
};

const result = (value: string): CompletionResult => ({
	items: [{ value, displayValue: value, description: null, kind: "command", matchedIndices: [] }],
	span: { start: 0, end: 0 },
	query: "",
});

describe("CompletionDispatcher", () => {
	it("delivers a provider's result to a listener", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		dispatcher.register(async () => result("git"));
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toHaveLength(1));
		expect(seen[0]?.items[0]?.value).toBe("git");
	});

	it("passes the line, cursor and cwd through to the provider", async () => {
		const dispatcher = new CompletionDispatcher(() => "/repo", host);
		let seen: CompletionRequest | null = null;
		dispatcher.register(async (request) => {
			seen = request;
			return null;
		});
		dispatcher.request("git co", 6);
		await vi.waitFor(() => expect(seen).not.toBeNull());
		expect(seen!.line).toBe("git co");
		expect(seen!.cursor).toBe(6);
		expect(seen!.cwd).toBe("/repo");
	});

	it("drops a stale result when a newer request has been made", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		let release: (() => void) | null = null;
		const gate = new Promise<void>((resolve) => {
			release = resolve;
		});
		let call = 0;
		dispatcher.register(async (request) => {
			call += 1;
			if (call === 1) {
				await gate;
				return result("stale");
			}
			return result("fresh");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));

		dispatcher.request("g", 1);
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toHaveLength(1));
		release!();
		await Promise.resolve();
		await Promise.resolve();

		expect(seen.map((entry) => entry?.items[0]?.value)).toEqual(["fresh"]);
	});

	it("aborts the previous request's signal when a new one arrives", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const signals: AbortSignal[] = [];
		dispatcher.register(async (request) => {
			signals.push(request.signal);
			return null;
		});
		dispatcher.request("g", 1);
		await vi.waitFor(() => expect(signals).toHaveLength(1));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(signals).toHaveLength(2));
		expect(signals[0]!.aborted).toBe(true);
		expect(signals[1]!.aborted).toBe(false);
	});

	it("emits null and aborts on cancel", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const signals: AbortSignal[] = [];
		dispatcher.register(async (request) => {
			signals.push(request.signal);
			return result("git");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(signals).toHaveLength(1));
		dispatcher.cancel();
		expect(signals[0]!.aborted).toBe(true);
		expect(seen.at(-1)).toBeNull();
	});

	it("emits null when no provider is registered", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});

	it("survives a provider that throws, emitting null", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		dispatcher.register(async () => {
			throw new Error("provider exploded");
		});
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});

	it("stops delivering to an unregistered provider", async () => {
		const dispatcher = new CompletionDispatcher(() => "/tmp", host);
		const dispose = dispatcher.register(async () => result("git"));
		dispose();
		const seen: (CompletionResult | null)[] = [];
		dispatcher.onResult((value) => seen.push(value));
		dispatcher.request("gi", 2);
		await vi.waitFor(() => expect(seen).toEqual([null]));
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/core test -- completions
```

Expected: FAIL — `Failed to resolve import "./completions.js"`.

- [ ] **Step 3: Add the host capability to `types.ts`**

Add above `HostCapabilities`:

```ts
export type DirEntry = Readonly<{
	name: string;
	isDirectory: boolean;
	isHidden: boolean;
}>;
```

and add one member to `HostCapabilities`:

```ts
	listDirectory?(path: string): Promise<readonly DirEntry[]>;
```

It is optional on purpose (D2): a host with no filesystem keeps every other provider.

- [ ] **Step 4: Write `completions.ts`**

```ts
import type { HostCapabilities } from "./types.js";

export type CompletionItem = Readonly<{
	value: string;
	displayValue: string;
	description: string | null;
	kind: string;
	matchedIndices: readonly number[];
}>;

export type CompletionResult = Readonly<{
	items: readonly CompletionItem[];
	span: Readonly<{ start: number; end: number }>;
	query: string;
}>;

export type CompletionRequest = Readonly<{
	line: string;
	cursor: number;
	cwd: string;
	host: HostCapabilities;
	signal: AbortSignal;
}>;

export type CompletionProvider = (request: CompletionRequest) => Promise<CompletionResult | null>;

export type CompletionListener = (result: CompletionResult | null) => void;

export class CompletionDispatcher {
	private provider: CompletionProvider | null = null;
	private readonly listeners = new Set<CompletionListener>();
	private controller: AbortController | null = null;
	private generation = 0;

	constructor(
		private readonly cwd: () => string,
		private readonly host: HostCapabilities,
	) {}

	register(provider: CompletionProvider): () => void {
		this.provider = provider;
		return () => {
			if (this.provider === provider) this.provider = null;
		};
	}

	onResult(listener: CompletionListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	request(line: string, cursor: number): void {
		const generation = this.beginGeneration();
		const provider = this.provider;
		if (provider === null) {
			this.emit(generation, null);
			return;
		}
		const request: CompletionRequest = {
			line,
			cursor,
			cwd: this.cwd(),
			host: this.host,
			signal: this.controller!.signal,
		};
		provider(request).then(
			(result) => this.emit(generation, result),
			() => this.emit(generation, null),
		);
	}

	cancel(): void {
		const generation = this.beginGeneration();
		this.emit(generation, null);
	}

	dispose(): void {
		this.controller?.abort();
		this.controller = null;
		this.listeners.clear();
		this.provider = null;
	}

	private beginGeneration(): number {
		this.controller?.abort();
		this.controller = new AbortController();
		this.generation += 1;
		return this.generation;
	}

	private emit(generation: number, result: CompletionResult | null): void {
		if (generation !== this.generation) return;
		for (const listener of [...this.listeners]) listener(result);
	}
}
```

- [ ] **Step 5: Wire it into `TerminalCore`**

In `terminal-core.ts`, construct one dispatcher in the same place the other per-core state
is built, passing a `cwd` getter that reads the last block's `cwd` from the decoded blocks
(`BlockView.cwd` already exists — `types.ts:18`, populated at `blocks.ts:55`), falling back
to `""` when there are no blocks yet. Add the five delegating methods named in
**Interfaces** above, and call `dispatcher.dispose()` from the core's existing dispose path.

Export from `index.ts`: `CompletionDispatcher` is internal, but the types
`CompletionItem`, `CompletionProvider`, `CompletionRequest`, `CompletionResult` and
`DirEntry` are public and must be added to the `export type` block.

- [ ] **Step 6: Run the whole core suite**

```bash
npm --prefix packages/terminal/ts/core test
```

Expected: PASS, including the 8 new tests. The pre-existing core tests must stay green — if
`HostCapabilities` gained a *required* member you have broken every existing host; it is
optional for exactly this reason.

- [ ] **Step 7: Commit**

```bash
git add packages/terminal/ts/core/src
git commit -m "feat(terminal): give the core a cancellable completion provider seam"
```

---

### Task 6: The path provider

**Files:**
- Create: `packages/terminal/ts/completions/src/providers/path.ts`
- Test: `packages/terminal/ts/completions/src/providers/path.test.ts`

**Interfaces:**
- Consumes: `Candidate` (Task 4), `Span`/`CompletionLocation` (Task 2), `TemplateType`
  (Task 1), `DirEntry` and `HostCapabilities` (Task 5).
- Produces:
  `pathCandidates(input: PathInput): Promise<Candidate[]>` where
  `PathInput = { query: string; cwd: string; template: TemplateType; host: HostCapabilities; signal: AbortSignal }`,
  and `splitPathQuery(query: string): { directory: string; leaf: string }`.

Because the host supplies `listDirectory`, this provider never touches a filesystem itself
and its tests never need one — the fake host is three lines.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/providers/path.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { pathCandidates, splitPathQuery } from "./path.js";

const entries = {
	"/repo": [
		{ name: "src", isDirectory: true, isHidden: false },
		{ name: "README.md", isDirectory: false, isHidden: false },
		{ name: ".git", isDirectory: true, isHidden: true },
	],
	"/repo/src": [{ name: "index.ts", isDirectory: false, isHidden: false }],
};

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
	listDirectory: async (path: string) =>
		entries[path as keyof typeof entries] ?? [],
};

const signal = new AbortController().signal;

describe("splitPathQuery", () => {
	it("splits a bare leaf into the current directory", () => {
		expect(splitPathQuery("REA")).toEqual({ directory: ".", leaf: "REA" });
	});

	it("splits a relative path at its last separator", () => {
		expect(splitPathQuery("src/ind")).toEqual({ directory: "src", leaf: "ind" });
	});

	it("splits a trailing separator into an empty leaf", () => {
		expect(splitPathQuery("src/")).toEqual({ directory: "src", leaf: "" });
	});

	it("keeps an absolute directory absolute", () => {
		expect(splitPathQuery("/repo/sr")).toEqual({ directory: "/repo", leaf: "sr" });
	});
});

describe("pathCandidates", () => {
	it("lists files and folders from the cwd", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("suffixes a directory with a separator so the next Tab descends", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value)).toEqual(["src/"]);
	});

	it("still offers directories when the template says files", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("resolves a subdirectory in the query against the cwd", async () => {
		const found = await pathCandidates({
			query: "src/",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value)).toEqual(["src/index.ts"]);
	});

	it("hides dotfiles until the query asks for one", async () => {
		const hidden = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(hidden.map((entry) => entry.value)).not.toContain(".git/");

		const asked = await pathCandidates({
			query: ".",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(asked.map((entry) => entry.value)).toContain(".git/");
	});

	it("returns nothing when the host cannot list directories", async () => {
		const bare = { ...host, listDirectory: undefined };
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host: bare,
			signal,
		});
		expect(found).toEqual([]);
	});

	it("returns nothing once the request is aborted", async () => {
		const controller = new AbortController();
		controller.abort();
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal: controller.signal,
		});
		expect(found).toEqual([]);
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- providers/path
```

Expected: FAIL — `Failed to resolve import "./path.js"`.

- [ ] **Step 3: Write `providers/path.ts`**

```ts
import type { HostCapabilities } from "@operator/terminal-core";
import type { Candidate } from "../rank.js";
import type { TemplateType } from "../signature.js";

export type PathInput = Readonly<{
	query: string;
	cwd: string;
	template: TemplateType;
	host: HostCapabilities;
	signal: AbortSignal;
}>;

export function splitPathQuery(query: string): { directory: string; leaf: string } {
	const index = query.lastIndexOf("/");
	if (index === -1) return { directory: ".", leaf: query };
	const directory = index === 0 ? "/" : query.slice(0, index);
	return { directory, leaf: query.slice(index + 1) };
}

export async function pathCandidates(input: PathInput): Promise<Candidate[]> {
	const list = input.host.listDirectory;
	if (list === undefined) return [];
	if (input.signal.aborted) return [];

	const { directory, leaf } = splitPathQuery(input.query);
	const absolute = directory.startsWith("/")
		? directory
		: directory === "."
			? input.cwd
			: `${input.cwd}/${directory}`;

	const entries = await list.call(input.host, absolute);
	if (input.signal.aborted) return [];

	const prefix = input.query.slice(0, input.query.length - leaf.length);
	const wantsHidden = leaf.startsWith(".");

	const candidates: Candidate[] = [];
	for (const entry of entries) {
		if (entry.isHidden && !wantsHidden) continue;
		if (input.template === "folders" && !entry.isDirectory) continue;
		const name = entry.isDirectory ? `${entry.name}/` : entry.name;
		candidates.push({
			value: `${prefix}${name}`,
			displayValue: name,
			kind: "path",
			isDirectory: entry.isDirectory,
		});
	}
	return candidates;
}
```

Only `folders` filters. A `files` template still offers directories, because a directory
is how you *reach* a file — filtering them out makes `git add src/index.ts` impossible to
complete past `src`. Warp's `Files` template behaves the same way; the filter belongs on
what is finally accepted, not on what is offered.

Note `displayValue` is the bare name while `value` carries the typed prefix. Warp has the
same split and flags it as a wart to fix later (`suggest/mod.rs:317-319`); we get the
correct behaviour for free because `rank` matches on `displayValue` (Task 4) while the
editor inserts `value`.

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test -- providers/path
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/completions/src/providers
git commit -m "feat(terminal): complete paths through the host, never the shell"
```

---

### Task 7: The flag provider

**Files:**
- Create: `packages/terminal/ts/completions/src/providers/flag.ts`
- Test: `packages/terminal/ts/completions/src/providers/flag.test.ts`

**Interfaces:**
- Consumes: `CommandSpec`, `OptSpec`, `clampPriority` (Task 1); `Candidate` (Task 4).
- Produces: `flagCandidates(command: CommandSpec, used: readonly string[]): Candidate[]`.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/providers/flag.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { flagCandidates } from "./flag.js";
import type { CommandSpec } from "../signature.js";

const commit: CommandSpec = {
	name: "commit",
	options: [
		{ name: ["-m", "--message"], description: "Commit message", priority: 60 },
		{ name: ["-a", "--all"], description: "Stage tracked files" },
		{ name: ["--amend"] },
	],
};

describe("flagCandidates", () => {
	it("offers every long and short form", () => {
		const found = flagCandidates(commit, []).map((entry) => entry.value);
		expect(found).toEqual(
			expect.arrayContaining(["-m", "--message", "-a", "--all", "--amend"]),
		);
	});

	it("carries the description through for the dropdown", () => {
		const message = flagCandidates(commit, []).find((entry) => entry.value === "--message");
		expect(message?.description).toBe("Commit message");
	});

	it("carries the declared priority", () => {
		const message = flagCandidates(commit, []).find((entry) => entry.value === "--message");
		expect(message?.priority).toBe(60);
	});

	it("defaults an undeclared priority to zero", () => {
		const amend = flagCandidates(commit, []).find((entry) => entry.value === "--amend");
		expect(amend?.priority).toBe(0);
	});

	it("drops an option once one of its forms is already on the line", () => {
		const found = flagCandidates(commit, ["-m"]).map((entry) => entry.value);
		expect(found).not.toContain("--message");
		expect(found).not.toContain("-m");
		expect(found).toContain("--amend");
	});

	it("returns nothing for a command with no options", () => {
		expect(flagCandidates({ name: "pwd" }, [])).toEqual([]);
	});
});
```

The fifth case is the behaviour that makes flag completion feel finished: once you have
typed `-m`, neither `-m` nor its alias `--message` should be offered again.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- providers/flag
```

Expected: FAIL — `Failed to resolve import "./flag.js"`.

- [ ] **Step 3: Write `providers/flag.ts`**

```ts
import type { Candidate } from "../rank.js";
import { clampPriority, optHasName, type CommandSpec } from "../signature.js";

export function flagCandidates(
	command: CommandSpec,
	used: readonly string[],
): Candidate[] {
	const usedNames = used
		.map((token) => token.replace(/^--?/, ""))
		.filter((name) => name.length > 0);

	const candidates: Candidate[] = [];
	for (const option of command.options ?? []) {
		if (usedNames.some((name) => optHasName(option, name))) continue;
		for (const name of option.name) {
			candidates.push({
				value: name,
				kind: "flag",
				description: option.description,
				priority: clampPriority(option.priority),
			});
		}
	}
	return candidates;
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test -- providers/flag
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts/completions/src/providers/flag.ts packages/terminal/ts/completions/src/providers/flag.test.ts
git commit -m "feat(terminal): complete a command's declared options"
```

---

### Task 8: The command provider, the three shipped specs, and the public entry point

**Files:**
- Create: `packages/terminal/ts/completions/src/providers/command.ts`
- Create: `packages/terminal/ts/completions/src/specs/git.ts`
- Create: `packages/terminal/ts/completions/src/specs/cd.ts`
- Create: `packages/terminal/ts/completions/src/specs/docker.ts`
- Create: `packages/terminal/ts/completions/src/specs/index.ts`
- Create: `packages/terminal/ts/completions/src/index.ts`
- Test: `packages/terminal/ts/completions/src/providers/command.test.ts`
- Test: `packages/terminal/ts/completions/src/index.test.ts`

**Interfaces:**
- Consumes: everything from Tasks 1–7, plus `CompletionProvider`, `CompletionResult`
  from `@operator/terminal-core` (Task 5).
- Produces:
  `commandCandidates(registry: SignatureRegistry): Candidate[]`,
  `subcommandCandidates(command: CommandSpec): Candidate[]`,
  `argumentCandidates(command: CommandSpec, position: number): { literals: Candidate[]; template: TemplateType | null }`,
  `defaultSignatures: readonly CommandSpec[]`,
  `createCompletionProvider(options?: { signatures?: readonly CommandSpec[] }): CompletionProvider`.

This is the task that makes the phase visible: it joins the location, the registry, the
three providers and the ranker into the one function a host registers.

- [ ] **Step 1: Write the three specs**

`specs/cd.ts`:

```ts
import type { CommandSpec } from "../signature.js";

export const cd: CommandSpec = {
	name: "cd",
	alias: ["chdir"],
	description: "Change the working directory",
	arguments: [
		{
			name: "directory",
			description: "Directory to change to",
			optional: true,
			values: [{ kind: "template", template: "folders" }],
		},
	],
};
```

`specs/git.ts` — at minimum `add`, `commit`, `checkout` (alias `co`), `push`, `status`,
`remote` (with `add`/`remove`), each with a description; `commit` carries
`-m/--message`, `-a/--all`, `--amend`; `add` and `checkout` take a
`files-and-folders` template argument; `checkout` gets `priority: 60` so it outranks
`cherry-pick` on `c`. Keep the file under 600 lines — it will be nowhere near.

`specs/docker.ts` — `run`, `build`, `ps`, `images`, `exec`, `logs`, with `build` taking a
`folders` template argument and `-t/--tag`, and `run` carrying `-it`, `--rm`, `-p/--publish`.

`specs/index.ts`:

```ts
import { cd } from "./cd.js";
import { docker } from "./docker.js";
import { git } from "./git.js";
import type { CommandSpec } from "../signature.js";

export const defaultSignatures: readonly CommandSpec[] = [cd, git, docker];

export { cd, docker, git };
```

- [ ] **Step 2: Write the failing tests**

`packages/terminal/ts/completions/src/providers/command.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { argumentCandidates, commandCandidates, subcommandCandidates } from "./command.js";
import { SignatureRegistry } from "../registry.js";
import { defaultSignatures, git } from "../specs/index.js";

const registry = SignatureRegistry.from(defaultSignatures);

describe("commandCandidates", () => {
	it("offers every registered root command", () => {
		const found = commandCandidates(registry).map((entry) => entry.value);
		expect(found).toEqual(expect.arrayContaining(["cd", "git", "docker"]));
	});

	it("marks them as commands", () => {
		expect(commandCandidates(registry)[0]?.kind).toBe("command");
	});
});

describe("subcommandCandidates", () => {
	it("offers a command's subcommands", () => {
		const found = subcommandCandidates(git).map((entry) => entry.value);
		expect(found).toEqual(expect.arrayContaining(["commit", "checkout", "push"]));
	});

	it("carries descriptions through", () => {
		const commit = subcommandCandidates(git).find((entry) => entry.value === "commit");
		expect(commit?.description).toBeTruthy();
	});

	it("returns nothing for a leaf command", () => {
		expect(subcommandCandidates({ name: "pwd" })).toEqual([]);
	});
});

describe("argumentCandidates", () => {
	it("reports the template an argument asks for", () => {
		const cd = registry.lookup("cd")!;
		expect(argumentCandidates(cd, 0).template).toBe("folders");
	});

	it("reports literal suggestions declared on an argument", () => {
		const command: Parameters<typeof argumentCandidates>[0] = {
			name: "npm",
			arguments: [
				{
					name: "script",
					values: [
						{ kind: "suggestion", suggestion: { value: "start" } },
						{ kind: "suggestion", suggestion: { value: "test", priority: 20 } },
					],
				},
			],
		};
		const { literals, template } = argumentCandidates(command, 0);
		expect(literals.map((entry) => entry.value)).toEqual(["start", "test"]);
		expect(literals[1]?.priority).toBe(20);
		expect(template).toBeNull();
	});

	it("reports nothing past the last declared argument", () => {
		const cd = registry.lookup("cd")!;
		expect(argumentCandidates(cd, 3)).toEqual({ literals: [], template: null });
	});

	it("keeps offering a variadic argument past its first position", () => {
		const command: Parameters<typeof argumentCandidates>[0] = {
			name: "rm",
			arguments: [
				{
					name: "file",
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
		};
		expect(argumentCandidates(command, 4).template).toBe("files-and-folders");
	});
});
```

`packages/terminal/ts/completions/src/index.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { createCompletionProvider } from "./index.js";

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
	listDirectory: async () => [
		{ name: "src", isDirectory: true, isHidden: false },
		{ name: "README.md", isDirectory: false, isHidden: false },
	],
};

const provider = createCompletionProvider();

const complete = (line: string, cursor = line.length) =>
	provider({ line, cursor, cwd: "/repo", host, signal: new AbortController().signal });

describe("createCompletionProvider", () => {
	it("completes a root command", async () => {
		const result = await complete("gi");
		expect(result?.items.map((item) => item.value)).toContain("git");
		expect(result?.span).toEqual({ start: 0, end: 2 });
	});

	it("completes a subcommand", async () => {
		const result = await complete("git comm");
		expect(result?.items[0]?.value).toBe("commit");
	});

	it("completes a subcommand by alias, ranked by priority", async () => {
		const result = await complete("git c");
		expect(result?.items[0]?.value).toBe("checkout");
	});

	it("completes a flag", async () => {
		const result = await complete("git commit --me");
		expect(result?.items.map((item) => item.value)).toContain("--message");
	});

	it("completes a folder for cd", async () => {
		const result = await complete("cd ");
		expect(result?.items.map((item) => item.value)).toEqual(["src/"]);
	});

	it("completes files and folders for git add", async () => {
		const result = await complete("git add ");
		expect(result?.items.map((item) => item.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("returns matched indices so the dropdown can highlight", async () => {
		const result = await complete("git cmt");
		const commit = result?.items.find((item) => item.value === "commit");
		expect(commit?.matchedIndices).toEqual([0, 2, 5]);
	});

	it("returns null for an unknown command's arguments", async () => {
		const result = await complete("kubectl get ");
		expect(result).toBeNull();
	});

	it("returns null inside a variable", async () => {
		expect(await complete("echo $HO")).toBeNull();
	});

	it("never calls the host for anything but a directory listing", async () => {
		const calls: string[] = [];
		const watched = {
			...host,
			writeClipboard: async () => {
				calls.push("writeClipboard");
			},
			openLink: async () => {
				calls.push("openLink");
			},
		};
		await provider({
			line: "git add ",
			cursor: 8,
			cwd: "/repo",
			host: watched,
			signal: new AbortController().signal,
		});
		expect(calls).toEqual([]);
	});
});
```

The last test is the one that pins Phase 4's first accept criterion in code. `HostCapabilities`
has no method that can run a command, so the strongest available proof is that the provider
reaches for nothing but `listDirectory`. Keep it.

- [ ] **Step 3: Run them and watch them fail**

```bash
npm --prefix packages/terminal/ts/completions test
```

Expected: FAIL — `Failed to resolve import "./command.js"` and `"./index.js"`.

- [ ] **Step 4: Write `providers/command.ts`**

```ts
import type { Candidate } from "../rank.js";
import type { SignatureRegistry } from "../registry.js";
import {
	clampPriority,
	isVariadic,
	type CommandSpec,
	type TemplateType,
} from "../signature.js";

export function commandCandidates(registry: SignatureRegistry): Candidate[] {
	return registry.commands().map((command) => ({
		value: command.name,
		kind: "command",
		description: command.description,
		priority: clampPriority(command.priority),
	}));
}

export function subcommandCandidates(command: CommandSpec): Candidate[] {
	return (command.subcommands ?? []).map((sub) => ({
		value: sub.name,
		kind: "subcommand",
		description: sub.description,
		priority: clampPriority(sub.priority),
	}));
}

export function argumentCandidates(
	command: CommandSpec,
	position: number,
): { literals: Candidate[]; template: TemplateType | null } {
	const args = command.arguments ?? [];
	const last = args[args.length - 1];
	const argument =
		args[position] ?? (last !== undefined && isVariadic(last) ? last : undefined);
	if (argument === undefined) return { literals: [], template: null };

	const literals: Candidate[] = [];
	let template: TemplateType | null = null;
	for (const value of argument.values ?? []) {
		if (value.kind === "suggestion") {
			literals.push({
				value: value.suggestion.value,
				displayValue: value.suggestion.displayValue,
				description: value.suggestion.description,
				kind: "argument",
				priority: clampPriority(value.suggestion.priority),
			});
		} else if (value.kind === "template") {
			template = value.template;
		}
	}
	return { literals, template };
}
```

- [ ] **Step 5: Write `index.ts`**

```ts
import type {
	CompletionItem,
	CompletionProvider,
	CompletionRequest,
	CompletionResult,
} from "@operator/terminal-core";
import { locate } from "./parse.js";
import { rank, type Candidate, type Ranked } from "./rank.js";
import { SignatureRegistry } from "./registry.js";
import { commandCandidates, subcommandCandidates, argumentCandidates } from "./providers/command.js";
import { flagCandidates } from "./providers/flag.js";
import { pathCandidates } from "./providers/path.js";
import { defaultSignatures } from "./specs/index.js";
import type { CommandSpec } from "./signature.js";

export type { CommandSpec, ArgumentSpec, OptSpec, ArgumentValue } from "./signature.js";
export { SignatureRegistry } from "./registry.js";
export { rank, tabAction } from "./rank.js";
export { locate } from "./parse.js";
export { defaultSignatures } from "./specs/index.js";

export function createCompletionProvider(
	options: { signatures?: readonly CommandSpec[] } = {},
): CompletionProvider {
	const registry = SignatureRegistry.from(options.signatures ?? defaultSignatures);

	return async (request: CompletionRequest): Promise<CompletionResult | null> => {
		const location = locate(request.line, request.cursor);
		if (location === null) return null;

		const candidates = await collect(registry, location, request);
		if (candidates === null) return null;

		const ranked = rank(candidates, location.query);
		return {
			items: ranked.map(toItem),
			span: location.span,
			query: location.query,
		};
	};
}

async function collect(
	registry: SignatureRegistry,
	location: ReturnType<typeof locate> & object,
	request: CompletionRequest,
): Promise<Candidate[] | null> {
	if (location.kind === "command") return commandCandidates(registry);

	const resolved = registry.resolve(location.commandTokens);
	if (resolved === null) return null;

	if (location.kind === "flag") {
		const used = location.commandTokens.filter((token) => token.startsWith("-"));
		return flagCandidates(resolved.command, used);
	}

	const position = location.commandTokens.length - resolved.consumed;
	const { literals, template } = argumentCandidates(resolved.command, position);
	const subcommands = position === 0 ? subcommandCandidates(resolved.command) : [];
	const paths =
		template === null
			? []
			: await pathCandidates({
					query: location.query,
					cwd: request.cwd,
					template,
					host: request.host,
					signal: request.signal,
				});
	return [...subcommands, ...literals, ...paths];
}

function toItem(entry: Ranked): CompletionItem {
	const { candidate, match } = entry;
	return {
		value: candidate.value,
		displayValue: candidate.displayValue ?? candidate.value,
		description: candidate.description ?? null,
		kind: candidate.kind,
		matchedIndices: match.kind === "fuzzy" ? match.indices : [],
	};
}
```

- [ ] **Step 6: Run the whole package suite and watch it pass**

```bash
npm --prefix packages/terminal/ts/completions test
```

Expected: PASS. If "completes a subcommand by alias, ranked by priority" fails with
`commit` instead of `checkout`, the `priority: 60` on `checkout` in `specs/git.ts` is
missing — fix the spec, not the ranker.

- [ ] **Step 7: Verify boundaries and line limits**

```bash
npm --prefix packages/terminal run check:boundaries
```

Expected: exit 0. `ts/completions` importing `@operator/terminal-core` is allowed
(`check-boundaries.mjs:129-132`).

- [ ] **Step 8: Commit**

```bash
git add packages/terminal/ts/completions
git commit -m "feat(terminal): join the completion engine behind one provider"
```

---

### Task 9: Never block a frame

**Files:**
- Create: `packages/terminal/ts/completions/src/schedule.ts`
- Modify: `packages/terminal/ts/completions/src/index.ts` — route ranking through the scheduler
- Test: `packages/terminal/ts/completions/src/schedule.test.ts`

**Interfaces:**
- Consumes: `Candidate`, `Ranked`, `rank` (Task 4).
- Produces:
  `FRAME_BUDGET_MS = 8`, `CHUNK_SIZE = 256`,
  `Scheduler = { now(): number; yield(): Promise<void> }`,
  `rankChunked(candidates: readonly Candidate[], query: string, signal: AbortSignal, scheduler?: Scheduler): Promise<Ranked[] | null>`.

The scheduler is injected as one object rather than a bare `now` because a test that fakes
the clock but not the yield can only assert on a counter, and a counter cannot tell you
whether the loop ever actually yielded.

Phase 4's second accept criterion is "completions are cancellable and never block a frame".
Cancellation landed in Task 5; this task is the other half. A directory with 20,000 entries
is the case that matters, and it is not hypothetical — `node_modules` exists.

The budget is 8 ms, half of a 60 Hz frame, leaving the other half for the paint that
§9.5 caps at one per frame. Yielding uses `setTimeout(…, 0)` rather than
`requestAnimationFrame` because `ts/completions` must run in a `node` test environment and
must not assume a DOM.

- [ ] **Step 1: Write the failing test**

`packages/terminal/ts/completions/src/schedule.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { rankChunked, FRAME_BUDGET_MS } from "./schedule.js";
import type { Candidate } from "./rank.js";

const many = (count: number): Candidate[] =>
	Array.from({ length: count }, (_, index) => ({
		value: `command-${index}`,
		kind: "command" as const,
	}));

const open = new AbortController().signal;

describe("rankChunked", () => {
	it("ranks a small set in one pass", async () => {
		const ranked = await rankChunked(many(10), "command-3", open);
		expect(ranked?.[0]?.candidate.value).toBe("command-3");
	});

	it("ranks a large set completely", async () => {
		const ranked = await rankChunked(many(20000), "command-19999", open);
		expect(ranked?.[0]?.candidate.value).toBe("command-19999");
	});

	it("yields rather than running past the frame budget in one go", async () => {
		let clock = 0;
		let yields = 0;
		const scheduler = {
			now: () => {
				clock += FRAME_BUDGET_MS;
				return clock;
			},
			yield: async () => {
				yields += 1;
			},
		};
		const ranked = await rankChunked(many(2000), "command", open, scheduler);
		expect(ranked).not.toBeNull();
		expect(yields).toBeGreaterThan(0);
	});

	it("does not yield when the whole set fits in one budget", async () => {
		let yields = 0;
		const scheduler = {
			now: () => 0,
			yield: async () => {
				yields += 1;
			},
		};
		await rankChunked(many(2000), "command", open, scheduler);
		expect(yields).toBe(0);
	});

	it("returns null when aborted partway", async () => {
		const controller = new AbortController();
		let clock = 0;
		const scheduler = {
			now: () => {
				clock += 1000;
				return clock;
			},
			yield: async () => {
				controller.abort();
			},
		};
		const ranked = await rankChunked(many(20000), "command", controller.signal, scheduler);
		expect(ranked).toBeNull();
	});

	it("returns null when it starts already aborted", async () => {
		const controller = new AbortController();
		controller.abort();
		expect(await rankChunked(many(10), "c", controller.signal)).toBeNull();
	});

	it("gives the same answer as the unchunked ranker", async () => {
		const candidates = many(500);
		const { rank } = await import("./rank.js");
		const chunked = await rankChunked(candidates, "c1", open);
		expect(chunked?.map((entry) => entry.candidate.value)).toEqual(
			rank(candidates, "c1").map((entry) => entry.candidate.value),
		);
	});
});
```

The last test is the one that keeps this honest: chunking must not change the answer.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/completions test -- schedule
```

Expected: FAIL — `Failed to resolve import "./schedule.js"`.

- [ ] **Step 3: Write `schedule.ts`**

```ts
import { matchQuery } from "./match.js";
import { orderByPriority, assemble, type Candidate, type Ranked } from "./rank.js";

export const FRAME_BUDGET_MS = 8;
export const CHUNK_SIZE = 256;

export type Scheduler = Readonly<{ now(): number; yield(): Promise<void> }>;

export const defaultScheduler: Scheduler = {
	now: () => Date.now(),
	yield: () =>
		new Promise((resolve) => {
			setTimeout(resolve, 0);
		}),
};

export async function rankChunked(
	candidates: readonly Candidate[],
	query: string,
	signal: AbortSignal,
	scheduler: Scheduler = defaultScheduler,
): Promise<Ranked[] | null> {
	if (signal.aborted) return null;

	const ordered = orderByPriority(candidates);
	const matched: Ranked[] = [];
	let sliceStart = scheduler.now();

	for (let index = 0; index < ordered.length; index += 1) {
		const candidate = ordered[index]!;
		const match = matchQuery(candidate.displayValue ?? candidate.value, query);
		if (match !== null) matched.push({ candidate, match });

		if ((index + 1) % CHUNK_SIZE === 0) {
			if (scheduler.now() - sliceStart >= FRAME_BUDGET_MS) {
				await scheduler.yield();
				if (signal.aborted) return null;
				sliceStart = scheduler.now();
			}
		}
	}

	return assemble(matched);
}
```

This requires two small refactors in `rank.ts`, both of which keep its existing public
behaviour: export `orderByPriority(candidates: readonly Candidate[]): Candidate[]` (the
sort currently inlined at the top of `rank`) and
`assemble(matched: readonly Ranked[]): Ranked[]` (the four-bucket partition and fuzzy sort
currently inlined at the bottom). Rewrite `rank` to call both, so the two code paths cannot
drift — that is what the "same answer as the unchunked ranker" test is guarding.

- [ ] **Step 4: Run the whole package suite**

```bash
npm --prefix packages/terminal/ts/completions test
```

Expected: PASS. Task 4's `rank.test.ts` must still be green after the refactor; if it is
not, `rank` no longer calls the two extracted helpers in the right order.

- [ ] **Step 5: Route the provider through the scheduler**

In `index.ts`, replace `const ranked = rank(candidates, location.query);` with:

```ts
		const ranked = await rankChunked(candidates, location.query, request.signal);
		if (ranked === null) return null;
```

and import `rankChunked` from `./schedule.js`. Re-run the package suite; `index.test.ts`
must stay green unchanged.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/ts/completions/src
git commit -m "feat(terminal): rank completions inside a frame budget, cancellably"
```

---

### Task 10: The dropdown, and taking Tab back

**Files:**
- Create: `packages/terminal/ts/editor/src/completions-dropdown.ts`
- Modify: `packages/terminal/ts/editor/src/keymap.ts` — add `complete`, move `accept-suggestion`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` — wire the dropdown
- Modify: `packages/terminal/ts/editor/src/styles.css` and `styles.ts` — dropdown chrome
- Test: `packages/terminal/ts/editor/src/completions-dropdown.test.ts`
- Test: `packages/terminal/ts/editor/src/keymap.test.ts` — repair the Tab tests
- Test: `packages/terminal/ts/editor/src/line-editor.test.ts` — repair the ghost-text tests

**Interfaces:**
- Consumes: `CompletionResult`, `CompletionItem` from `@operator/terminal-core` (Task 5).
  **Not** `@operator/terminal-completions` — that import is a CI failure
  (`check-boundaries.mjs:144-145`).
- Produces: `CompletionsDropdown` with `mount(container)`, `setResult(result | null)`,
  `handleKey(event): boolean`, `selected(): CompletionItem | null`, `isOpen(): boolean`,
  `close()`, `dispose()`.

Read D5 first. `keymap.ts:69-70` currently gives Tab to `accept-suggestion`; this task takes
it for completions and gives ghost-text acceptance to `→` (at end of line) and `Ctrl-E`.
Existing tests assert the old binding — repair them, do not delete them.

- [ ] **Step 1: Write the failing dropdown test**

`packages/terminal/ts/editor/src/completions-dropdown.test.ts`:

```ts
import { beforeEach, describe, expect, it } from "vitest";
import { CompletionsDropdown } from "./completions-dropdown.js";

const item = (value: string, description: string | null = null) => ({
	value,
	displayValue: value,
	description,
	kind: "subcommand",
	matchedIndices: [] as number[],
});

const result = (...values: string[]) => ({
	items: values.map((value) => item(value)),
	span: { start: 4, end: 6 },
	query: "co",
});

let container: HTMLElement;
let dropdown: CompletionsDropdown;

beforeEach(() => {
	document.body.innerHTML = "";
	container = document.createElement("div");
	document.body.append(container);
	dropdown = new CompletionsDropdown();
	dropdown.mount(container);
});

const key = (name: string) =>
	new KeyboardEvent("keydown", { key: name, cancelable: true });

describe("CompletionsDropdown", () => {
	it("is closed until it is given a result", () => {
		expect(dropdown.isOpen()).toBe(false);
		expect(container.querySelector("[data-terminal-completions]")).toBeNull();
	});

	it("renders one row per item", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(container.querySelectorAll("[data-completion-row]")).toHaveLength(2);
	});

	it("selects the first row by default", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("moves the selection down and back up", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(dropdown.handleKey(key("ArrowDown"))).toBe(true);
		expect(dropdown.selected()?.value).toBe("checkout");
		expect(dropdown.handleKey(key("ArrowUp"))).toBe(true);
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("wraps the selection at both ends", () => {
		dropdown.setResult(result("commit", "checkout"));
		dropdown.handleKey(key("ArrowUp"));
		expect(dropdown.selected()?.value).toBe("checkout");
		dropdown.handleKey(key("ArrowDown"));
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("marks the selected row for the stylesheet", () => {
		dropdown.setResult(result("commit", "checkout"));
		dropdown.handleKey(key("ArrowDown"));
		const rows = container.querySelectorAll("[data-completion-row]");
		expect(rows[1]?.getAttribute("data-selected")).toBe("true");
		expect(rows[0]?.getAttribute("data-selected")).toBe("false");
	});

	it("closes on Escape and reports the key as handled", () => {
		dropdown.setResult(result("commit"));
		expect(dropdown.handleKey(key("Escape"))).toBe(true);
		expect(dropdown.isOpen()).toBe(false);
	});

	it("ignores keys while closed", () => {
		expect(dropdown.handleKey(key("ArrowDown"))).toBe(false);
	});

	it("closes when given a null result", () => {
		dropdown.setResult(result("commit"));
		dropdown.setResult(null);
		expect(dropdown.isOpen()).toBe(false);
	});

	it("closes when given an empty result", () => {
		dropdown.setResult({ items: [], span: { start: 0, end: 0 }, query: "" });
		expect(dropdown.isOpen()).toBe(false);
	});

	it("renders a description when the item carries one", () => {
		dropdown.setResult({
			items: [item("commit", "Record changes")],
			span: { start: 0, end: 0 },
			query: "",
		});
		expect(container.textContent).toContain("Record changes");
	});

	it("highlights the fuzzy-matched characters", () => {
		dropdown.setResult({
			items: [{ ...item("commit"), matchedIndices: [0, 2, 5] }],
			span: { start: 0, end: 0 },
			query: "cmt",
		});
		const marks = container.querySelectorAll("[data-completion-match]");
		expect([...marks].map((mark) => mark.textContent)).toEqual(["c", "m", "t"]);
	});

	it("removes its element on dispose", () => {
		dropdown.setResult(result("commit"));
		dropdown.dispose();
		expect(container.querySelector("[data-terminal-completions]")).toBeNull();
	});
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix packages/terminal/ts/editor test -- completions-dropdown
```

Expected: FAIL — `Failed to resolve import "./completions-dropdown.js"`.

- [ ] **Step 3: Write `completions-dropdown.ts`**

Implement `CompletionsDropdown` to satisfy the test exactly: an element carrying
`data-terminal-completions`, appended to the container on the first non-empty result and
removed on close; one `data-completion-row` per item with `data-selected="true"|"false"`;
the display text split so that every index in `matchedIndices` is wrapped in a
`<span data-completion-match>`; the description in a trailing span; `handleKey` returning
`true` only for `ArrowDown`, `ArrowUp`, `Escape`, `Enter` and `Tab` **while open**, and
`false` otherwise so the editor keeps every other key. Keep the file under 600 lines.

- [ ] **Step 4: Run it and watch it pass**

```bash
npm --prefix packages/terminal/ts/editor test -- completions-dropdown
```

Expected: PASS, 13 tests.

- [ ] **Step 5: Rebind Tab in `keymap.ts`**

Add `| { kind: "complete" }` to `EditorCommand`. Change the `case "Tab":` arm to return
`{ kind: "complete" }`. Add an `ArrowRight` arm that returns `{ kind: "accept-suggestion" }`
when the cursor is at end of line — the keymap does not know the cursor, so return
`{ kind: "accept-suggestion" }` for `ArrowRight` only when `ctrlKey` is false and let
`line-editor.ts` fall back to `{ kind: "move", delta: 1 }` when the cursor is not at the
end. Add `Ctrl-E` → `{ kind: "accept-suggestion" }`. In `passthroughFor`, map
`"complete"` to `"\t"` (so a `Released`/`Unknown` pane still sends a literal Tab to the
program, which is what a TUI expects) and keep `"accept-suggestion"` mapping to `"\t"`
unchanged.

Repair `keymap.test.ts`: the existing assertion that `Tab` produces `accept-suggestion`
becomes `complete`, and add assertions for `ArrowRight` and `Ctrl-E`.

- [ ] **Step 6: Wire the dropdown into `line-editor.ts`**

In `mount`, construct a `CompletionsDropdown`, mount it into the same container, and
subscribe with `core.onCompletions((result) => dropdown.setResult(result))`, keeping the
unsubscribe alongside the existing one for disposal.

In `onKeyDown`, give the dropdown first refusal — `if (dropdown.handleKey(event)) { event.preventDefault(); return; }`
— **but only after** the existing reverse-search branch, which already owns the keyboard
when open.

In `apply`, add a `case "complete":` that calls
`core.requestCompletions(this.buffer.text, this.buffer.cursor)`. When the dropdown is open
and `Enter` or `Tab` is pressed, replace `[span.start, span.end)` in the buffer with the
selected item's `value`, close the dropdown, and re-request so a directory completion
immediately offers its contents.

In `apply`'s `case "accept-suggestion":`, leave the existing history-suggestion behaviour
untouched — it now arrives from `→`/`Ctrl-E` instead of Tab.

Any text-mutating command (`insert`, `delete-backward`, `delete-forward`,
`delete-word-backward`) must call `core.cancelCompletions()` when the dropdown is open, so
a stale list never survives an edit.

Repair `line-editor.test.ts`: tests that press Tab expecting ghost-text acceptance now press
`ArrowRight`; add a test that Tab calls `requestCompletions` with the buffer's text and
cursor, and a test that typing a character while the dropdown is open calls
`cancelCompletions`.

- [ ] **Step 7: Style the dropdown**

Add rules to `packages/terminal/ts/editor/src/styles.css` for
`.terminal-completions`, `.terminal-completion-row`,
`.terminal-completion-row[data-selected="true"]`, `.terminal-completion-match` and
`.terminal-completion-description`, using the existing `--terminal-*` custom properties
only — no literal colours. Mirror them into `styles.ts`. `styles-parity.test.ts` already
exists in this package and will fail if the two drift; run it.

- [ ] **Step 8: Run the whole editor and core suites**

```bash
npm --prefix packages/terminal test
```

Expected: PASS across every workspace package.

- [ ] **Step 9: Commit**

```bash
git add packages/terminal/ts/editor/src
git commit -m "feat(terminal): show completions in the editor, and give Tab back to them"
```

---

### Task 11: The gate, the boundaries, and the spec record

**Files:**
- Modify: `packages/terminal/scripts/check-boundaries.mjs` — only if Task 8 revealed a gap
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` — §14 Phase 4, §4.1, §10.1
- Test: `packages/terminal/scripts/check-boundaries.test.mjs`

- [ ] **Step 1: Prove the boundary rule is actually enforced**

Add a case to `packages/terminal/scripts/check-boundaries.test.mjs` asserting that a file
under `ts/editor` importing `@operator/terminal-completions` is reported as
`"editor must not import completions"`. If a case already covers it, verify it runs and move
on. Then sabotage: temporarily add
`import { rank } from "@operator/terminal-completions";` to
`packages/terminal/ts/editor/src/line-editor.ts` and run:

```bash
npm --prefix packages/terminal run check:boundaries
```

Expected: **non-zero exit**, naming the file and the rule. Revert the sabotage.

- [ ] **Step 2: Run the perf gate**

```bash
npm --prefix packages/terminal run bench:gate
```

Expected: exit 0 with a printed verdict per scenario. Phase 4's fourth accept criterion is
"the §9.4 gate still passes", and §9.4 is explicit that this must be the command's verdict,
not arithmetic done by hand off a report. If `input-latency-owned` regressed past 16.7 ms,
the cause is the editor doing completion work on the keystroke path — the fix is that
`requestCompletions` is fire-and-forget and the dropdown updates from the listener, never
awaited inline.

- [ ] **Step 3: Record the phase in the spec**

Amend `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`:

- **§4.1** — add `listDirectory?(path: string): Promise<readonly DirEntry[]>` to the
  `HostCapabilities` block with the `DirEntry` type, and one sentence saying it is optional
  because a host without a filesystem must keep every other provider (D2). Cite Warp's
  `EngineDirEntry` (`completer/engine/path.rs:36-51`) as the shape.
- **§10.1** — replace "(phase 4) a completions dropdown" with a statement that the dropdown
  landed, that it reaches completions through `core.onCompletions` /
  `core.requestCompletions`, and that Tab now means completion while `→` and `Ctrl-E` accept
  the ghost-text history suggestion (D5).
- **§14 Phase 4** — mark it landed with the date, and record the two deviations that
  outlive the phase: **no generators** (D1, with the `signatures/v2/mod.rs:104-118`
  citation and the §3.6 reason) and **the fuzzy scorer is ours, not SkimMatcherV2** (D3,
  with the constants living in `ts/completions/SPEC.md`). Record `LocationType::Variable` as
  deferred (D4) so a later phase picks it up deliberately rather than discovering it.

- [ ] **Step 4: Commit**

```bash
git add packages/terminal/scripts docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md
git commit -m "spec: close phase 4 -- completions, with the two deviations from Warp"
```

---

## Self-Review

**Executed audit, 2026-08-30.** Every algorithm in this plan was run against its own tests
before the plan was handed off, rather than reviewed by reading. Six defects were found and
fixed; they are listed here because each one would have cost an implementer a red suite with
no obvious cause.

| # | Where | Defect | Resolution |
| --- | --- | --- | --- |
| 1 | Task 2 `locate` | With the cursor in leading whitespace (`"  git"`, offset 1) it returned a `command` location instead of `null`, so Tab would insert *before* the existing token. | Added the `tokens.some((token) => token.span.start >= clamped)` guard. |
| 2 | Task 2 test | Asserted `query === "co"` at offset 7 of `"git commit -m"`; `commit` spans 4–10 so the query is `"com"`. | Test corrected. |
| 3 | Task 4 test | "prefix ahead of fuzzy" used `cmt`/`commit` against `"cm"` — but `cmt` *is* a prefix match, so the expected order was inverted. | Candidates changed to `c-m-x`/`cmt`. |
| 4 | Task 4 test | The case-sensitivity test had only one prefix match, so `tabAction` returned `insert` via the single-prefix shortcut and never reached the common-prefix filter it was meant to exercise. | Rewritten with two prefix matches (`Commit-tree`/`commit-message`). |
| 5 | Task 6 `pathCandidates` | A `files` template filtered directories out, making any nested file — `git add src/index.ts` — impossible to complete past `src`. | Only `folders` filters now. |
| 6 | Task 9 test | The fake clock advanced 1 ms per call, so with `CHUNK_SIZE = 256` the budget was never reached: zero yields, and `clock > 8` was false. The test asserted yielding while proving the opposite. | `Scheduler` is injected as `{ now, yield }` so a test can observe yields directly. |

Defects 3, 4 and 6 share a shape worth naming: each was a test whose *expectation* was
wrong, and each would have looked like an implementation bug to whoever hit it. Defects 1
and 5 were real implementation bugs, and 5 was user-visible.


**Spec coverage.** §14 Phase 4's deliverables map one-to-one: `ts/completions` is Task 1's
package; "the provider interface on the core" is Task 5; "path, flag and git subcommand
providers" are Tasks 6, 7 and 8; "fuzzy ranking" is Tasks 3 and 4; "the dropdown UI" is
Task 10; "a declarative spec format for per-command completions" is Task 1 plus the three
specs in Task 8. The four accept criteria: no shell execution is structural (D1 — the
variant does not exist) and pinned by Task 8's last test; cancellable-and-never-blocks is
Tasks 5 and 9; three commands and a documented schema are Task 8's specs and Task 1's
`SPEC.md`; the §9.4 gate is Task 11 Step 2. §4.3's enforcement is exercised by sabotage in
Task 11 Step 1 rather than assumed.

**Warp fidelity.** Four mechanisms are copied with citations verified on 2026-08-30:
the location union (`engine/mod.rs:35-58`), the signature format (`signatures/v2/mod.rs:19-58, 194-208`),
the ranking order (`suggest/mod.rs:311-315, 405-416`) and Tab's three-way behaviour
(`suggest/mod.rs:459-513`). Two deviations are recorded with reasons rather than smuggled
in: generators (D1) and the scorer (D3). D3 exists because the `fuzzy-matcher` crate is
**not** vendored into the Warp checkout — `~/.cargo/registry` has no `fuzzy-matcher-*`
directory — so its constants could not be read, and inventing numbers while claiming to
port SkimMatcherV2 is the failure mode the previous plan in this series was corrected for.

**Placeholder scan.** Three steps deliberately describe rather than quote, and each names
the exact file and the exact rule to satisfy: Task 8 Step 1's `git.ts`/`docker.ts` contents
(the schema is fully specified in Task 1 and the required commands and priorities are
listed), Task 10 Step 3's dropdown DOM (fully pinned by the 13 assertions written
immediately above it) and Task 10 Step 6's `line-editor.ts` wiring (each edit is named with
its method and its ordering constraint). These are data and integration, not undefined
behaviour. No step says "add error handling" or "write tests for the above".

**Type consistency.** `Candidate`/`Ranked`/`CandidateKind` are defined in Task 4 and used
under those names in Tasks 6, 7, 8 and 9. `Span` is defined in Task 2 and consumed by Task
4's `tabAction`. `CompletionResult`/`CompletionItem`/`CompletionProvider`/`CompletionRequest`
are defined in Task 5 and are what Task 8 returns and Task 10 consumes. `TemplateType` is
defined in Task 1 and threaded through Tasks 6 and 8. `clampPriority` (Task 1) is called in
Tasks 4, 7 and 8. Task 9 introduces `orderByPriority` and `assemble` as **extractions from**
Task 4's `rank`, and Task 9 Step 3 says so explicitly so nobody writes a second sort.

**Ordering risk.** Task 5 is the only task that must land before its consumers, and it
depends on nothing from `ts/completions` — the dependency runs one way, which is what makes
§10.1 satisfiable at all. Tasks 6 and 7 are independent of each other. Task 9 refactors code
Task 4 wrote and is therefore ordered after it, with the "same answer as the unchunked
ranker" test as the guard. Task 10 is last among the implementation tasks because it needs
a working provider to wire.

**Known limits, deliberately out of scope.** Variable completion (D4). Dynamic argument
values of any kind (D1) — including the read-only, synchronous variety §3.6 would permit,
because deciding that needs a spec change, not a task here. Completion of a command inside
another command's argument (`sudo git …`): the `ArgumentValue` union carries the
`root-command` variant so the format can express it, but no provider acts on it in Phase 4;
`argumentCandidates` returns it in neither `literals` nor `template`, which is a silent
no-op worth revisiting. And the spec format ships three commands because that is the accept
criterion; a real completion catalogue is a content problem, not an engineering one.
