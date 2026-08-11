# opr start

Fetch (if needed) and open the Operator desktop app. The desktop app owns the daemon, state, and updates. `opr start` no longer runs a daemon: it resolves the installed app (or downloads the latest release), opens it, and exits.

## Syntax

```
opr start [flags]
```

## Flags

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output start result as JSON | - |

## Examples

```bash
# Open the Operator desktop app
opr start
```

```bash
# Open the app and get the result as JSON
opr start --json
```
