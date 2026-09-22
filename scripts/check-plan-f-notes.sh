#!/bin/sh
set -e
root=/Users/omaraly/development/AI/Operator-plan-f
fail=0
grep -q "predictive echo" "$root/TERMINAL.md" || { echo "FAIL TERMINAL.md has no predictive-echo gap entry"; fail=1; }
grep -q "2026-09-22-server-owned-terminal-model-design.md" "$root/TERMINAL.md" || { echo "FAIL TERMINAL.md does not point at the 4.2 spec"; fail=1; }
grep -q "2026-09-22-remote-typing-latency-measurement.md" "$root/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md" || { echo "FAIL Part 6 note does not cite the measurement"; fail=1; }
grep -q "2026-09-22-server-owned-terminal-model-design.md" "$root/docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md" || { echo "FAIL Part 6 note does not cite the 4.2 spec"; fail=1; }
[ "$fail" -eq 0 ] || exit 1
echo "PASS Plan F notes recorded"
