# Quick Reference

Natural-language-to-command mappings for common Operator tasks.

| You want to... | Command |
|---|---|
| Show me this webpage / open this page | `opr preview "<url>"` |
| Start an existing configured dev app | `opr preview start [configuration]` |
| Check or stop the worker's managed dev app | `opr preview status` / `opr preview stop` |
| Show this Markdown or HTML file without a server | `opr preview "<workspace-path>"` |
| Hand off a newly created browser-displayable artifact | `opr preview "<workspace-path>"` immediately after writing the primary artifact |
| Inspect and verify this webpage as the agent | `opr browser open "<url>"`, then `opr browser snapshot` |
| Click or fill a page element | `opr browser snapshot`, then `opr browser click <ref>` or `opr browser fill <ref> "<text>"` |
| Check frontend runtime failures | `opr browser errors` and `opr browser console` |
| Diagnose a request/API/CORS/auth/redirect failure when normal page evidence is insufficient | `opr browser network start`, reproduce once, then `opr browser network stop` |
| Check network capture without enabling it | `opr browser network status` or `opr browser network list` |
| Open the user's real Chromium debugging surface | `opr browser devtools open` |
| Close the shared DevTools window when explicitly requested | `opr browser devtools close` |
| Capture the page | `opr browser screenshot [path]` |
| Spawn a worker on issue N | `opr spawn --project <p> --issue N --name "<=20 chars>" --prompt "..."` |
| Message a running agent | `opr send --session <id> --message "..."` |
| Kill a session | `opr session kill <id>` |
| List sessions | `opr session ls` |
| Register a repo as a project | `opr project add --path <abs-path> --name <name>` |
| List projects | `opr project ls` |
| Rename a session | `opr session rename <id> "<name>"` |
| Restore a killed session | `opr session restore <id>` |
| Clean up terminated sessions | `opr session cleanup` |
| Make a Docker container this session starts survive Operator cleanup | `docker run --label opr.session=$OPERATOR_SESSION_ID --label opr.spare=true ...` |
| See a session's details | `opr session get <id>` |
| Open the desktop app | `opr start` |
| Check the daemon is up | `opr status` |
| Run health checks | `opr doctor` |
| Clear the preview panel | `opr preview clear` |
| List orchestrator sessions | `opr orchestrator ls` |
| Claim an existing PR for a session | `opr session claim-pr <id> <pr-ref>` |
| Submit a code review verdict | `opr review submit <session-id> --run <run-id> --verdict approved` |
| Configure a project's default branch or model | `opr project set-config <id> --default-branch <branch> --model <model>` |
| Import projects from a legacy Operator install | `opr import --dry-run` (preview), then `opr import -y` |
