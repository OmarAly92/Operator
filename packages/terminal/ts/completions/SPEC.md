# `@operator/terminal-completions` Schema

This package defines the data shape that completion providers hand to the
engine. A provider returns a `CommandSpec`; the engine walks it, descends
through subcommands, and renders suggestions against the current input. The
shape is a strict, statically typed subset of the Warp `signatures/v2` model
(see `signatures/v2/mod.rs` in the Warp upstream), tightened to remove the
shell-out variant the spec document for Operator forbids.

Specs are TypeScript modules, not JSON. The provider owns the file, the
engine imports it, and the type checker is the contract.

## Worked example: `git commit`

This is the same fixture `registry.test.ts` builds in code. The provider
ships a file that looks like this:

```ts
import type { CommandSpec } from "@operator/terminal-completions";

export const spec: CommandSpec = {
	name: "git",
	subcommands: [
		{
			name: "commit",
			options: [{ name: ["-m", "--message"] }],
		},
		{ name: "checkout", alias: ["co"] },
		{
			name: "remote",
			subcommands: [
				{ name: "add" },
				{ name: "remove", alias: ["rm"] },
			],
		},
	],
};
```

The engine resolves the input `git remote rm` against this spec, descends
through `git` -> `remote` -> `remove` (matched by alias), and produces
`{ command, consumed: 3 }`.

## Field tables

### `CommandSpec`

| Field         | Type                         | Optional | Default       |
| ------------- | ---------------------------- | -------- | ------------- |
| `name`        | `string`                     | no       | -             |
| `alias`       | `readonly string[]`          | yes      | `[]`          |
| `description` | `string`                     | yes      | -             |
| `arguments`   | `readonly ArgumentSpec[]`    | yes      | `[]`          |
| `subcommands` | `readonly CommandSpec[]`     | yes      | `[]`          |
| `options`     | `readonly OptSpec[]`         | yes      | `[]`          |
| `priority`    | `number` (clamped, see below)| yes      | `0`           |

### `ArgumentSpec`

| Field         | Type                          | Optional | Default |
| ------------- | ----------------------------- | -------- | ------- |
| `name`        | `string`                      | no       | -       |
| `description` | `string`                      | yes      | -       |
| `values`      | `readonly ArgumentValue[]`    | yes      | `[]`    |
| `optional`    | `boolean`                     | yes      | `false` |
| `arity`       | `Arity`                       | yes      | -       |

### `OptSpec`

| Field         | Type                          | Optional | Default       |
| ------------- | ----------------------------- | -------- | ------------- |
| `name`        | `readonly string[]`           | no       | -             |
| `description` | `string`                      | yes      | -             |
| `arguments`   | `readonly ArgumentSpec[]`     | yes      | `[]`          |
| `required`    | `boolean`                     | yes      | `false`       |
| `priority`    | `number` (clamped, see below) | yes      | `0`           |

An option's first argument is what gets completed after the option, in both forms the
engine understands: `--file <TAB>` as a separate token, and `--file=<TAB>` where only the
text right of the `=` is replaced. Give that argument `values` if the option takes a path
or a fixed set — `--file` taking a `files` template is why `docker build --file=` offers
files rather than nothing.

**Declare `arguments` on every option that takes a value.** It is not decoration: the
engine counts positional arguments by walking the tokens after the command, and it skips
an option's value only when the option says it has one. An undeclared `-t` in
`docker build -t img .` makes `img` look like the first positional argument, and the build
context never gets completed. The `=` form (`--tag=img`) is counted as a single token
regardless.

Each entry in `name` is one declared form of the option, e.g. `"-f"` and
`"--force"`. The engine looks them up with the hyphens stripped (see
`optHasName`).

### `Arity`

| Field      | Type     | Optional | Default     |
| ---------- | -------- | -------- | ----------- |
| `limit`    | `number` | yes      | -           |
| `delimiter`| `string` | yes      | -           |

When `limit` is omitted the argument is variadic. `delimiter` is only
meaningful when `limit` is omitted or greater than 1 and is the string the
engine splits multiple values on.

### `SuggestionSpec`

| Field          | Type    | Optional | Default     |
| -------------- | ------- | -------- | ----------- |
| `value`        | `string`| no       | -           |
| `displayValue` | `string`| yes      | `value`     |
| `description`  | `string`| yes      | -           |
| `priority`     | `number`| yes      | `0`         |

## The three `ArgumentValue` kinds

A positional `ArgumentSpec` may carry a `values` list. Each entry is one of:

1. **`suggestion`** - a static candidate with its own display text and
   description.
   ```ts
   {
   	kind: "suggestion",
   	suggestion: { value: "main", displayValue: "main", description: "default branch" },
   }
   ```
2. **`template`** - the engine should expand a filesystem template.
   ```ts
   { kind: "template", template: "files-and-folders" }
   ```
3. **`root-command`** - the value is the literal text the user has typed
   for the enclosing root command, useful for `sudo` / `xargs` style
   wrappers.
   ```ts
   { kind: "root-command" }
   ```

## Priority rule

`clampPriority` takes a `number | undefined` and returns an integer in the
closed interval `[-100, 100]`. `undefined`, `NaN`, and `Infinity` collapse
to `0`. Anything outside the range is clamped to the nearer end.

The engine uses the result to order suggestions within a single match
tier: higher priority sorts first, ties broken by `displayValue` ascending.
This matches the convention used by Warp's `Signature` parser
(`signatures/v2/mod.rs`).

## Why there is no generator

Warp's fourth `ArgumentValue` variant runs a shell command to compute its
candidates at completion time (`signatures/v2/mod.rs:104-118`). The
Operator terminal spec explicitly forbids provider-side shell execution:
section 3.6 ("Provider sandbox") rules out any completion path that would
require the engine to invoke a child process on the user's behalf. A
dynamic-values feature would need a spec decision first - specifically,
how a provider would register a sandboxed callback that returns a list
instead of running a script, and what the security review for that
callback would look like. Until that decision is made, the engine only
accepts `suggestion`, `template`, and `root-command`.

## Fuzzy scoring

`matchQuery(text, query)` first tries an exact match, then a prefix
match, then falls through to a subsequence (fuzzy) match. Case
sensitivity follows the smart-case rule: a query is case-insensitive
while every character is lowercase and becomes case-sensitive as soon
as it contains an uppercase letter. When a query is all lowercase the
haystack is folded to lowercase before comparison, so `"readme"` matches
`"README"`; when the query is mixed case the original casing of both
sides is compared byte-for-byte, so `"README"` no longer matches
`"readme"`.

The fuzzy tier scores each candidate by the table below and returns
`null` when the query is not a subsequence of the text. The same
five constants are exported from `match.ts` so a future tuning change
can update the table and the code in one place.

| Constant            | Value | Rule |
| ------------------- | ----- | ---- |
| `BONUS_FIRST_CHAR`  | `24`  | Awarded when the first query character lands on index 0 of the text. |
| `BONUS_WORD_START`  | `16`  | Awarded when a query character lands after a word separator (`/ - _ . space : @`) or at a camelCase boundary (previous character is lowercase, current is uppercase, current has a lowercase form). |
| `BONUS_CONSECUTIVE` | `8`   | Awarded when a query character immediately follows the previous matched character. |
| `PENALTY_GAP`       | `3`   | Subtracted per intervening character between two matched characters that are not consecutive. |
| `MAX_GAP_PENALTY`   | `12`  | Caps the per-gap penalty so a single wide gap cannot dominate the score. |

Warp implements the same algorithm as `SkimMatcherV2`
(`crates/fuzzy_match/src/lib.rs:81-83`) - the smart-case rule, the
word-start bonus, and the consecutive-run bonus all originate there.
This scorer is a behavioural equivalent written from the same rules,
not a port: the constants above are our values and may diverge on
purpose. If a tuning change moves a constant, update this table in the
same commit.
