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
