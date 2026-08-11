# opr status

Show Operator daemon status. Use this to verify the daemon is up and check which port it is bound to.

## Syntax

```
opr status [flags]
```

## Flags

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output status as JSON | - |

## Examples

```bash
# Check daemon status
opr status
```

```bash
# Get status as JSON (e.g. to check port programmatically)
opr status --json
```
