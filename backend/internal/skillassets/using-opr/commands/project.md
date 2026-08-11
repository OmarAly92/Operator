# opr project

Manage projects: register repos, inspect, configure per-project settings, and remove.

## Syntax

```
opr project <subcommand> [args] [flags]
```

## Subcommands

---

### opr project add

Register a local git repo as a project so sessions can be spawned in it. The path must be an existing git repository on disk. With `--as-workspace`, the path may be a parent folder containing direct child git repositories; Operator initializes/adopts the parent as the root repo and gitignores children.

**Syntax:**
```
opr project add [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--as-workspace` | Register a parent folder as a workspace project (root-as-repo plus direct child repos) | - |
| `--id string` | Project id | Derived by the daemon from the path |
| `--name string` | Display name | - |
| `--orchestrator-agent string` | Default orchestrator session agent | - |
| `--path string` | Absolute path to the local git repo | Required |
| `--worker-agent string` | Default worker session agent | - |

**Examples:**

```bash
# Register a repo as a project
opr project add --path /Users/harshit/Downloads/side-quests/operator --name "operator"
```

```bash
# Register a workspace (parent folder containing multiple repos)
opr project add --path /Users/harshit/Downloads/side-quests --as-workspace --name "side-quests"
```

---

### opr project ls

List registered projects. Aliases: `ls`, `list`.

**Syntax:**
```
opr project ls [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output projects as JSON | - |

**Examples:**

```bash
# List all registered projects
opr project ls
```

---

### opr project get

Fetch one registered project.

**Syntax:**
```
opr project get <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output project as JSON | - |

**Examples:**

```bash
# Get details for the operator project
opr project get operator
```

---

### opr project rm

Remove a registered project. Aliases: `rm`, `remove`, `delete`.

**Syntax:**
```
opr project rm <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--json` | Output removal result as JSON | - |
| `-y, --yes` | Skip confirmation prompt | - |

**Examples:**

```bash
# Remove a project (with confirmation)
opr project rm operator
```

```bash
# Remove without prompt
opr project rm operator -y
```

---

### opr project set-config

Replace a project's per-project config (branch, session prefix, env, symlinks, post-create, agent model/permissions, role overrides, worker rules, and orchestrator rules). The config is resolved when a session spawns. Set fields via flags, pass the whole object with `--config-json`, or `--clear` to remove all config.

**Syntax:**
```
opr project set-config <id> [flags]
```

**Flags:**

| Flag | Meaning | Default / Required |
|---|---|---|
| `--agent-rules string` | Project-specific standing instructions appended to worker session prompts | - |
| `--agent-rules-file string` | Repo-relative file containing project-specific worker standing instructions | - |
| `--clear` | Clear all config | - |
| `--config-json string` | Full config as a JSON object (overrides field flags) | - |
| `--default-branch string` | Base branch new session worktrees are created from | - |
| `--env stringArray` | Env var `KEY=VALUE` forwarded into sessions (repeatable) | - |
| `--json` | Output the updated project as JSON | - |
| `--model string` | Agent model override (e.g. `claude-opus-4-5`) | - |
| `--orchestrator-agent string` | Harness override for orchestrator sessions | - |
| `--orchestrator-rules string` | Project-specific standing instructions appended to orchestrator session prompts | - |
| `--permission string` | Permission mode: `default`, `accept-edits`, `auto`, `bypass-permissions` | - |
| `--post-create stringArray` | Command to run after workspace creation (repeatable) | - |
| `--session-prefix string` | Displayed session-id prefix | - |
| `--symlink stringArray` | Repo-relative path to symlink into workspaces (repeatable) | - |
| `--worker-agent string` | Harness override for worker sessions | - |

**Examples:**

```bash
# Set default branch and model for a project
opr project set-config operator --default-branch main --model claude-opus-4-5
```

```bash
# Set an env var and a post-create command
opr project set-config operator --env "NODE_ENV=development" --post-create "npm install"
```

```bash
# Set worker and orchestrator standing rules
opr project set-config operator --agent-rules "Run focused tests before reporting done." --orchestrator-rules "Delegate implementation work to worker sessions."
```

```bash
# Load worker rules from a repo-relative file
opr project set-config operator --agent-rules-file docs/opr-worker-rules.md
```
