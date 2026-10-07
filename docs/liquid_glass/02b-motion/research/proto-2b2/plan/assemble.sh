set -e
cd "$(dirname "$0")"
REPO=$(git rev-parse --show-toplevel)
python3 gen_tasks.py template-c.md
cat template-a.md template-b.md template-0.md template-c.md template-d.md > template.md
python3 - <<'PY'
from pathlib import Path
text = Path("template.md").read_text()
replay = Path("replay-result.txt").read_text().strip()
Path("template.md").write_text(text.replace("@@REPLAY@@", replay))
PY
RESULTS=""
if [ -f results.json ]; then RESULTS="--results results.json"; fi
python3 build_plan.py template.md "$REPO/docs/liquid_glass/02b-motion/plan-2b2.md" --repo "$REPO" $RESULTS
