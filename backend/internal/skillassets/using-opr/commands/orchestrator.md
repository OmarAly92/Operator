# opr orchestrator

Manage orchestrator sessions.

## Syntax

```
opr orchestrator <subcommand> [flags]
```

## Subcommands

---

### opr orchestrator ls

List orchestrator sessions. Aliases: `ls`, `list`.

**Syntax:**
```
opr orchestrator ls [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output as JSON | - |

## Examples

```bash
# List all orchestrator sessions
opr orchestrator ls
```

```bash
# List orchestrator sessions as JSON
opr orchestrator ls --json
```
