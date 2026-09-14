# Claude accounts — probe evidence

Recorded 2026-09-14 on macOS (Darwin 25.5.0) against Claude Code **2.1.267**.
No secret was read: Keychain probes list entry names and date attributes only,
and identity fields are compared as truncated sha256 hashes.

## P1. A `CLAUDE_CONFIG_DIR` folder has its own login lookup

```bash
claude auth status                                   # loggedIn: true,  authMethod: claude.ai
CLAUDE_CONFIG_DIR=<empty scratch dir> claude auth status   # loggedIn: false, authMethod: none
ls -A <empty scratch dir>                            # .claude.json  .claude.json.lock  backups
```

- An empty folder reports logged out while the default is logged in.
- Claude writes the global config **inside** the folder
  (`$CLAUDE_CONFIG_DIR/.claude.json`), not at `~/.claude.json`.

## P2. Logging in to a second folder adds a Keychain entry and leaves the default intact

After the user ran `CLAUDE_CONFIG_DIR=$HOME/.claude-work claude` and `/login`:

| Keychain service name | cdat (UTC) | mdat (UTC) |
|---|---|---|
| `Claude Code-credentials` | 2026-08-21 11:41:13 | 2026-09-14 10:26:19 |
| `Claude Code-credentials-6ed7293c` | 2026-09-14 16:04:51 | 2026-09-14 16:04:51 |

- The default entry was not modified by the second login.
- `claude auth status` stayed `loggedIn: true` for the default.

## P3. The Keychain suffix is sha256 of the exact absolute folder path

```
sha256("/Users/omaraly/.claude-work")[:8]   = 6ed7293c   ← matches
sha256("/Users/omaraly/.claude-work/")[:8]  = f9faffdb
sha256("~/.claude-work")[:8]                = 250d1b22
```

After `mv ~/.claude-work ~/.claude-personal`:

- `CLAUDE_CONFIG_DIR=$HOME/.claude-personal claude auth status` → `loggedIn: false`.
- Expected new entry name `Claude Code-credentials-30c38298`; the old
  `-6ed7293c` entry remains, orphaned.

Consequences: a folder can never be moved or renamed after login; the path must
be passed byte-identical on every launch (no trailing slash, no `~`, no
symlink-resolved variant); and setting `CLAUDE_CONFIG_DIR=$HOME/.claude` for the
default account would look up `Claude Code-credentials-<hash>` and appear
logged out.

## P4. The email Claude reports does not identify the account

`claude auth status` for both folders:

| Field | default `~/.claude` | `~/.claude-work` |
|---|---|---|
| `subscriptionType` | `max` | `pro` |
| `email` (hash) | `27a3920c` | `27a3920c` |
| `orgId` (hash) | same | same |
| `oauthAccount.accountUuid` in `.claude.json` (hash) | `ee4be4c8` | `ee4be4c8` |

- The pre-login backup of the work `.claude.json` held 2 keys and no
  `oauthAccount`, so the details were written during `/login`, not copied at
  first start.
- The two logins are different subscriptions yet report identical email, org and
  account id. Root cause not established; the user chose to stop the
  investigation. Operator therefore must not use the reported email or account id
  to tell accounts apart.

## P5. First launch in an empty folder writes real files

Claude's first run in `~/.claude-work` created `settings.json` (keys
`agentPushNotifEnabled`, `theme`), `plugins/` (`known_marketplaces.json`,
`marketplaces/`), `projects/`, `sessions/`, `cache/` and `backups/`. Shared links
must exist before the first launch or Claude creates real files in their place.

## P6. The default setup that a new folder would lack

`~/.claude` holds `CLAUDE.md`, `settings.json` (keys include `hooks`,
`permissions`, `model`, `effortLevel`, `enabledPlugins`), `skills/` (7 entries),
`commands/` (1), `plugins/` (11). `~/.claude.json` holds one user-scope MCP server
(`pencil`).

`~/.claude/plugins/installed_plugins.json` stores 8 absolute paths, all under
`/Users/omaraly/.claude/plugins` or the user's own project folders, so a linked
`plugins/` directory resolves correctly from any account folder.
