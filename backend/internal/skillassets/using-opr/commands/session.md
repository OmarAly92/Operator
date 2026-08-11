# opr session

Manage agent sessions: list, inspect, rename, kill, restore, clean up, and claim PRs.

## Syntax

```
opr session <subcommand> [args] [flags]
```

## Subcommands

---

### opr session ls

List sessions.

**Syntax:**
```
opr session ls [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `-a, --all` | Include orchestrator sessions | - |
| `--include-terminated` | Include terminated sessions | - |
| `--json` | Output as JSON | - |
| `-p, --project string` | Filter by project ID | - |

**Examples:**

```bash
# List all active worker sessions
opr session ls
```

```bash
# List all sessions including terminated, scoped to one project
opr session ls --include-terminated -p operator
```

---

### opr session get

Fetch one session.

**Syntax:**
```
opr session get <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output as JSON | - |
| `-p, --project string` | Project id to scope the lookup | - |

**Examples:**

```bash
# Get details for session mer-3
opr session get mer-3
```

```bash
# Get session details as JSON
opr session get mer-3 --json
```

---

### opr session kill

Terminate a session.

**Syntax:**
```
opr session kill <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `-p, --project string` | Project id to scope the lookup | - |

**Examples:**

```bash
# Kill session mer-3
opr session kill mer-3
```

---

### opr session rename

Rename a session.

**Syntax:**
```
opr session rename <id> <name> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `-p, --project string` | Project id to scope the lookup | - |

**Examples:**

```bash
# Rename session mer-3 to a new display name
opr session rename mer-3 "fix-auth-bug"
```

---

### opr session restore

Relaunch a terminated session.

**Syntax:**
```
opr session restore <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `-p, --project string` | Project id to scope the lookup | - |

**Examples:**

```bash
# Restore a terminated session
opr session restore mer-3
```

---

### opr session cleanup

Clean up terminated sessions by reclaiming eligible workspaces. Dirty worktrees are skipped by the daemon.

**Syntax:**
```
opr session cleanup [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `-p, --project string` | Filter by project ID | - |
| `-y, --yes` | Skip confirmation prompt | - |

**Examples:**

```bash
# Clean up all terminated sessions (skip prompt)
opr session cleanup -y
```

```bash
# Clean up terminated sessions for one project
opr session cleanup -p operator
```

---

### opr session claim-pr

Attach an existing PR to a session.

**Syntax:**
```
opr session claim-pr <session-id> <pr-ref> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output as JSON | - |
| `--no-takeover` | Refuse if another active session owns the PR | - |
| `-p, --project string` | Project id to scope the lookup | - |

**Examples:**

```bash
# Attach PR 88 to session mer-3
opr session claim-pr mer-3 88
```

```bash
# Claim PR 88 but refuse if another session already owns it
opr session claim-pr mer-3 88 --no-takeover
```
