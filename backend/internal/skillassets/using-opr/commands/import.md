# opr import

Import reads the legacy Operator flat-file store (`~/.operator`) read-only and ports its projects and per-project settings into the rewrite database. Legacy files are never modified, and a re-run skips rows that already exist, so it is safe to run more than once. The daemon must be stopped before running: it is the sole writer of the database.

## Syntax

```
opr import [flags]
```

## Flags

| Flag | Meaning | Default / Required |
|---|---|---|
| `--dry-run` | Parse and report the planned import without writing | - |
| `--from string` | Legacy Operator root to read | `~/.operator` |
| `--json` | Output the import report as JSON | - |
| `-y, --yes` | Skip the confirmation prompt (for non-interactive use) | - |

## Examples

```bash
# Preview what would be imported without writing anything
opr import --dry-run
```

```bash
# Run the import non-interactively
opr import -y
```

```bash
# Import from a custom legacy path
opr import --from /tmp/old-operator -y
```
