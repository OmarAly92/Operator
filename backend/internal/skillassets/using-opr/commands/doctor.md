# opr doctor

Run local Operator health checks. Use this to diagnose setup problems or verify the environment is correctly configured.

## Syntax

```
opr doctor [flags]
```

## Flags

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output health checks as JSON | - |

## Examples

```bash
# Run health checks
opr doctor
```

```bash
# Get health check results as JSON
opr doctor --json
```
