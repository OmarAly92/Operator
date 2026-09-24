# Operator MCP: remaining harnesses

**Status:** open. This is the rest of phase 5 of `docs/plans/kanban-mcp.md`.

**Date:** 2026-09-24

**Branch:** `claude/wizardly-mayer-7w2oss`

This page lists every agent harness that still has to register the Operator MCP
server, and gives the details needed to finish each one. The main plan
(`kanban-mcp.md`) has the design; this page has only the remaining work.

## What is already done

These harnesses are wired. The table says how each was checked. "Real CLI" means the
installed CLI connected to `opr mcp` or parsed the exact config Operator generates.

| Harness | Mechanism | How it was checked |
| --- | --- | --- |
| Claude Code | inline `--mcp-config` JSON; `--allowedTools mcp__operator` | real daemon passed the flags to a real `claude` |
| Codex | `-c mcp_servers.operator={…,default_tools_approval_mode="approve"}` | codex-cli 0.156.1 parsed the exact flag and kept the user's servers |
| OpenCode | `mcp.operator` in the per-session `opencode.json` (`OPENCODE_CONFIG`) | opencode 1.18.32 `mcp list` connected to `opr mcp` |
| Qwen | `--mcp-config` inline JSON with `trust:true` | CLI help and bundled source (`parseMcpConfig`, `assembleMcpServers`) |
| Amp | `--mcp-config` with a bare server map | real `amp mcp list` showed the server; settings file not written |
| Copilot | `--additional-mcp-config` (shape from `copilot mcp add`) plus `--allow-tool=operator` | CLI help and the file `copilot mcp add` writes |
| Auggie | `--mcp-config` inline `{"mcpServers":…}` | bundled source (`qto`, `Wzn`) |
| Crush | `mcp.operator` and `permissions.allowed_tools` (`mcp_operator_<tool>`) in the workspace `.crush.json` | `crush schema`; the `mcp_%s_%s` format string in the binary |
| Kilo | `mcp.operator` and `"operator_*":"allow"` in `KILO_CONFIG_CONTENT` | real `kilo mcp list` connected to `opr mcp` |

## What is left

| # | Harness | Adapter | Likely channel | Confidence |
| --- | --- | --- | --- | --- |
| 1 | Droid | `adapters/agent/droid` | workspace `.factory/mcp.json` | **verified**: real droid connected |
| 2 | Cline | `adapters/agent/cline` | Cline's MCP settings file | unverified |
| 3 | Continue (`cn`) | `adapters/agent/continueagent` | generated config via `--config`, or a workspace `.continue/mcpServers/*.yaml` block | unverified |
| 4 | Grok | `adapters/agent/grok` | `grok mcp` / settings file | unverified |
| 5 | Autohand | `adapters/agent/autohand` | `--config <path>` or `.autohand/config.json` | unverified |
| 6 | Pi | `adapters/agent/pi` | probably no MCP client → unsupported | unverified |
| 7 | Cursor | `adapters/agent/cursor` | workspace `.cursor/mcp.json` | unverified |
| 8 | Goose | `adapters/agent/goose` | `--with-extension "<cmd>"` on `goose run`/`session` | unverified |
| 9 | Kiro | `adapters/agent/kiro` | `mcpServers` in the agent file the adapter already writes | high: the adapter already writes an empty `mcpServers` |
| 10 | Kimi | `adapters/agent/kimi` | `--mcp-config-file` or `config.toml` under `KIMI_CODE_HOME` | unverified |
| 11 | Vibe | `adapters/agent/vibe` | `[[mcp_servers]]` in `config.toml` under `VIBE_HOME` | unverified |
| 12 | Agy | `adapters/agent/agy` | Gemini-style `mcpServers` in `.gemini/settings.json` | unverified |
| 13 | Devin | `adapters/agent/devin` | `.devin/config.local.json` | unverified |
| 14 | Muse | `adapters/agent/muse` | unknown | unverified |
| 15 | Kimchi | `adapters/agent/kimchi` | `.kimchi/` settings | unverified |
| 16 | Prime Agent | `adapters/agent/primeagent` | unknown (adapter writes a TS plugin) | unverified |
| — | Aider | `adapters/agent/aider` | no MCP client → record as unsupported | high |

## Building blocks already in the code

Use these; do not re-derive them.

- **`ports.MCPServerSpec`** reaches every adapter in three places:
  - `ports.LaunchConfig.MCPServers`
  - `ports.RestoreConfig.MCPServers`
  - `ports.WorkspaceHookConfig.MCPServers`, which arrives in `GetAgentHooks`

  The session manager fills all three for every worker session
  (`session_manager/mcp.go`, `operatorMCPServers`). Reviewer sessions get none.
- **`ports.OperatorMCPServerName`** is `"operator"`.
- **`ports.OperatorMCPToolNames`** lists the server's tools, for CLIs that approve
  tools by exact name. A cli test pins it to what `opr mcp` really registers.
- **`agentbase`** (`adapters/agent/agentbase/mcp.go`):
  - `MCPServersMap(servers, opts…)` builds the common `{command,args,env}` map.
    The options are `WithStdioType` and `WithTrust`.
  - `MCPServersJSON(servers, opts…)` wraps that map as `{"mcpServers":…}` for an
    inline flag.
  - `WithoutEnv(servers)`: use it for any file inside the workspace (see the rule
    below).
  - `MCPServerNames(servers)`.
- **Instructions.** The board rules are `ports.OperatorMCPInstructions`. Any adapter
  that does not implement `ports.MCPInstructionsSurfacer` automatically gets them in
  its standing system prompt as a `## Operator board` section, but only when the
  server is registered. Implement `SurfacesMCPServerInstructions() bool { return true }`
  only if you have verified that the CLI puts MCP server `instructions` in the
  model's context.
- **Reference implementations**, one per mechanism:

  | Mechanism | Adapter |
  | --- | --- |
  | Inline flag | `claudecode`, `qwen`, `auggie`, `amp`, `copilot` |
  | Env-var config | `kilocode` |
  | Per-session config file in the prompt dir | `opencode` |
  | Merge into a workspace file, with uninstall | `crush/mcp.go` |

## Rules every harness must follow

1. **Use the launch's mechanism in this order:**
   1. a per-launch flag, applied in both `GetLaunchCommand` and
      `GetRestoreCommand`;
   2. an Operator-owned config file or env var the adapter already uses;
   3. a workspace file the adapter already writes for hooks.
2. **A workspace file means no `Env`.** In `in_place` mode several sessions share one
   checkout, so the file must not carry `OPERATOR_SESSION_ID`. Register
   `command=<opr> args=["mcp"]` only, and let `opr mcp` inherit the session identity
   from the agent process, exactly as the hooks do. This was verified on Droid: the
   server connected with the id coming only from the environment.
3. **Remove what you add.** Take the entry out in `UninstallHooks` /
   `CleanupWorkspace`, and keep the user's own servers and keys (see `crush/mcp.go`).
   Otherwise a leftover entry makes `opr mcp` fail outside an Operator session every
   time the user runs that CLI by hand.
4. **Keep the user's servers.** Never use a "strict" or "only these servers" option.
5. **Pre-approve the operator tools** when the CLI has a per-server or per-tool
   allow rule; a permission prompt on `session_report` would itself park the card in
   Needs you. If the CLI has no such rule, leave it and write it down.
6. **Clearing the report** needs the harness's hooks to emit `user-prompt-submit`, or
   untagged activity signals. Check `adapters/agent/<h>/activity.go`. If neither
   holds, write it down: the report would then stay until the next idle→active
   transition.

## Per-harness details

### 1. Droid, next up: verified, not yet written

- **Today:** the adapter writes the workspace `.factory/hooks.json` (`droid/hooks.go`,
  a `hooksjson.Manager`) and a runtime settings file under
  `<dataDir>/agent-runtime/droid/`, passed with `--settings`.
- **Verified with droid 0.226.2 (npm `droid`):**
  - `droid mcp add` writes `~/.factory/mcp.json` as
    `{"mcpServers":{"<name>":{"type":"stdio","command":…,"args":[…],"env":{…},"disabled":false}}}`.
  - A **workspace `.factory/mcp.json`** with that shape and **no env** shows as
    `operator stdio connected [project]` in `droid mcp list`, with the id inherited
    from the environment.
  - `mcpServers` in the `--settings` runtime file did **not** show up in
    `droid mcp list`, so do not rely on it.
- **Do:**
  - In `GetAgentHooks`, merge `mcpServers.operator` (no env, `type: "stdio"`) into
    `<ws>/.factory/mcp.json`, keeping the user's entries.
  - Add `.factory/mcp.json` to `hookutil.EnsureWorkspaceGitignore`, the way Crush
    does for its prompt file.
  - Remove the entry in `UninstallHooks`, and delete the file if Operator created it
    and it is now empty.
- **Worth writing:** a small `agentbase` helper, `MergeMCPServersFile(path,
  servers, opts)` / `RemoveMCPServersFile(path, name)`. It should read the JSON,
  update `mcpServers.<name>` only, and write it atomically with
  `hookutil.AtomicWriteFile`. Cursor, Agy and Devin can reuse it.
- **Approvals:** Droid has `droid mcp permissions` (persistent); nothing per-launch
  was found. Rely on the autonomy level Operator already passes.
- **Test:** the fake home and workspace recipe below, then
  `OPERATOR_SESSION_ID=x droid mcp list` in the workspace.

### 2. Cline

- **Today:** the adapter writes `.clinerules` in the workspace and reads
  `~/.cline/data/settings/providers.json`.
- **To find out:** npm `cline` 3.0.65 installed, but no `cline` binary appeared in
  `node_modules/.bin`. Check its `bin` in `package.json`. Cline keeps MCP servers in
  `cline_mcp_settings.json` under its data dir (`~/.cline/data/settings/`), with
  `{"mcpServers":{…,"autoApprove":["tool",…],"disabled":false}}`.
- **Do:** if the CLI has a data-dir flag or env var, point it at a per-session copy.
  Otherwise merge into the user's settings file only if there is no other way, and
  document that choice: it touches `~`.
- **Approvals:** `autoApprove: ports.OperatorMCPToolNames`.

### 3. Continue (`cn`, @continuedev/cli 1.5.47)

- **Today:** the adapter writes into `~/.continue/config.yaml`. Read `continueagent/`
  for exactly what it touches.
- **Known:**
  - `cn --mcp <slug>` accepts hub slugs only.
  - `cn --config <path>` replaces the whole assistant config.
  - `cn --allow <tool>` pre-approves a tool.
- **To find out:** whether `cn` loads a workspace `.continue/mcpServers/*.yaml` block.
  Continue's IDE extension does. If it does, write
  `.continue/mcpServers/operator.yaml` (`name`, `version`, `schema: v1`,
  `mcpServers: [{name, command, args}]`) without env, and remove it on uninstall.
- **Approvals:** `--allow <name>` for each tool. Confirm how `cn` names MCP tools first.

### 4. Grok (@vibe-kit/grok-cli 0.0.34)

- **Today:** the adapter writes `.claude/settings.local.json` in the workspace, which
  is Grok's Claude-compatible hook file.
- **To find out:** `grok mcp --help`, and where `grok mcp add` writes (run it with a
  fake `HOME` and read the file back, as done for Copilot and Droid).
- **Do:** use whatever the file or flag is. If Grok reads a project `.mcp.json` or
  `.grok/settings.json`, merge there without env.

### 5. Autohand (npm `autohand-cli` 0.9.8)

- **Today:** the adapter writes `.autohand/config.json` and uses `AUTOHAND_CONFIG`.
- **Known:** `autohand --config <path>` is the config file path
  (default `~/.autohand/config.json`).
- **To find out:** the MCP key in that config. Search the bundled JS in
  `node_modules/autohand-cli` for `mcpServers` / `mcp`.
- **Do:** add the server to the config the adapter already controls.

### 6. Pi (@earendil-works/pi-coding-agent 0.87.1)

- **Known:** its help lists extensions (`pi install/remove/list`) and
  `PI_CODING_AGENT_DIR`, but nothing about MCP.
- **To find out:** whether any extension or package gives it an MCP client.
  Pi's design deliberately leaves MCP out.
- **Likely outcome:** unsupported. Record it in `docs/architecture.md` and do nothing
  else. There is no fallback, by decision.

### 7. Cursor (`cursor-agent`, not on npm; install script)

- **Today:**
  - the adapter writes `.cursor/hooks.json` and `rules/` in the workspace,
    `~/.cursor/cli-config.json`, and a trust state file under the data dir;
  - it implements `AugmentRuntimeEnv` and `CleanupWorkspace`;
  - its hooks include `beforeMCPExecution`, mapped to `permission-request`.
- **Likely channel:** the workspace `.cursor/mcp.json`
  (`{"mcpServers":{…}}`, Claude shape), which `cursor-agent` reads for the project.
- **Do:** merge without env, remove in `CleanupWorkspace`, and gitignore it. Check
  whether `cursor-agent` needs `--approve-mcps` (or similar) for project servers to
  start without a prompt.

### 8. Goose (binary)

- **Today:** `[env GOOSE_MODE=<mode>] goose run …`; the adapter writes hooks under
  `.agents/`, and reads `config.yaml` under `XDG_CONFIG_HOME`.
- **Likely channel:** `goose run`/`goose session` take `--with-extension "<command>"`,
  a stdio MCP extension for this run only. Environment variables go inline as
  `KEY=VAL cmd`.
- **Do:** append `--with-extension "<opr> mcp"`, shell-quoting the path. The env can
  be inherited, because it is a per-launch flag.
- **To find out:** approval behaviour under each `GOOSE_MODE`, and whether goose
  surfaces server instructions. Its extensions have "instructions", so check.

### 9. Kiro (`kiro-cli`, binary)

- **Today:** `GetAgentHooks` writes the agent file `.kiro/agents/opr.json`.
  `setKiroAgentDefaults` in `kiro/hooks.go` already sets `"mcpServers": {}` and
  `"includeMcpJson": true`.
- **Do:**
  - Fill `mcpServers.operator` with `{command, args}` (no env) from
    `cfg.MCPServers`.
  - Today the defaults loop skips keys that already exist, so the operator entry has
    to be merged into the existing map rather than replacing it.
  - Add `"@operator"` to `allowedTools` (Kiro/Amazon Q syntax for "all tools of that
    server"). Confirm it against the installed `kiro-cli`.
  - Remove both in `UninstallHooks`.

### 10. Kimi (binary; `kimi`)

- **Today:**
  - uses `KIMI_CODE_HOME`, `config.toml`, a workspace-trust dir and `AGENTS.md`;
  - implements `AugmentRuntimeEnv` and `PreLaunch`;
  - launches with `kimi [--auto|-y]`, and resumes with `kimi --session …`.
- **Likely channel:** `kimi --mcp-config-file <path>` (JSON, Claude shape) or
  `--mcp-config <json>`. Confirm against `kimi --help`.
- **Do:** prefer the per-launch flag, with a file in the prompt dir if it needs a
  path.

### 11. Vibe (Mistral; binary)

- **Today:** the adapter writes `.vibe/hooks.toml`, an agent TOML under
  `VIBE_HOME/agents/`, and `config.toml` under `VIBE_HOME`.
- **Likely channel:** `[[mcp_servers]]` tables in `config.toml`, with `name`,
  `transport = "stdio"`, `command` and `args`.
- **Do:** if `VIBE_HOME` is per-session (check `AugmentRuntimeEnv`), write there with
  env. Otherwise use no env and merge carefully.

### 12. Agy (Antigravity; binary)

- **Today:** `agy --add-dir <WorkspacePath> …`; the adapter writes `.gemini/hooks.json`.
- **Likely channel:** Gemini-style `mcpServers` in `.gemini/settings.json`, with
  `trust: true`. Check whether `agy` accepts Gemini's `--mcp-config`-like flags; if
  so, prefer the flag.

### 13. Devin (binary)

- **Today:** the adapter writes `.devin/config.local.json`, and in `PreLaunch` reads
  `~/.claude.json` and `~/.local/share/devin/cli/trusted_workspaces.json`.
- **To find out:** the Devin CLI's MCP config key. It already reads `~/.claude.json`,
  so it may honour Claude-style `mcpServers` in `.devin/config.local.json` or a
  project `.mcp.json`.

### 14. Muse (binary)

- **Today:** `[env TBH_EVAL_APPEND_DEVELOPER_PROMPT=… TBH_MANAGED_HOOKS_PATH=…] muse
  --trust-workspace …`; hooks go under `<dataDir>/agent-hooks/muse/`, and it has a
  `CleanupWorkspace`.
- **To find out:** whether Muse has an MCP client at all, and whether it has a
  `TBH_*` env var for MCP config. It already takes developer prompt and hooks paths
  through env.

### 15. Kimchi (binary; related npm packages `@kimchi-dev/cli`, `@earendil-works/pi-coding-agent`)

- **Today:** the adapter writes `.kimchi/hooks.local.json` and reads
  `~/.config/kimchi/config.json`. Its code notes that Kimchi uses Claude-style rules
  (`mcp__server__tool`), so it likely has an MCP client.
- **To find out:** the config key, which is probably Claude-shape `mcpServers` in a
  `.kimchi/*.json`.
- **Approvals:** likely `mcp__operator` in an allow list, as Claude Code does.

### 16. Prime Agent (binary)

- **Today:** `prime-agent --…`; the adapter writes an `opr-activity.ts` plugin under
  `<dataDir>/agent-runtime/`.
- **To find out:** whether it has MCP support at all, or whether a plugin could expose
  tools instead. That would not be MCP, so it is out of scope unless it has a real
  MCP client.

### Aider

No MCP client. Record it as unsupported in `docs/architecture.md`; no code.

## How to check a harness without an account

None of this needs a login. `mcp list` / `mcp add` style subcommands work offline and
show the effective config.

```bash
S=/tmp/opr-mcp-check && mkdir -p $S/home $S/ws
cd backend && go build -o $S/opr ./cmd/opr            # the real server
cd $S && npm i <package>                                # or the vendor's install script
export HOME=$S/home XDG_CONFIG_HOME=$S/home/.config XDG_DATA_HOME=$S/home/.local/share

# 1. Learn the native format: let the CLI write it, then read it back.
<cli> mcp add operator -- $S/opr mcp && cat <the file it wrote>

# 2. Check Operator's generated config: flag, env var or file, whichever the
#    adapter uses. The id comes only from the environment, as in production.
cd $S/ws && OPERATOR_SESSION_ID=opr-1 OPERATOR_RUN_FILE=$S/nope.json <cli> [flags] mcp list
```

"connected" in the list proves the CLI started `opr mcp` and completed the MCP
handshake. With no daemon running, tool calls return a clean "daemon is not running"
tool error, and that is expected.

The unit test for each harness follows `crush/mcp_test.go` (file merge and uninstall)
or `qwen/mcp_launch_test.go` (flag on launch and restore).

## When a harness is finished

- Add its row to "What is already done" above.
- Update the Operator MCP section of `docs/architecture.md`.
- Run `go test ./internal/adapters/agent/<h>/ ./internal/session_manager/` and check
  the exit code, not piped output.
- Run the pinned lint:
  `go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run ./internal/adapters/agent/<h>/...`
