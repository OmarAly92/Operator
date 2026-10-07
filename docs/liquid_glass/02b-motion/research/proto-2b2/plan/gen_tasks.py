import sys
from pathlib import Path

HARNESS = "cd packages/mobile && python3 -m unittest "
PKG = "cd packages/mobile/packages/ios_liquid_glass && flutter test --no-pub "
EXAMPLE = "cd packages/mobile/packages/ios_liquid_glass/example && flutter test --no-pub "
APP = "cd packages/mobile && flutter test --no-pub "
H = "tool/glass_lab/harness/tests/"

GATES = {
    "package": [("pkg-analyze", "cd packages/mobile/packages/ios_liquid_glass && flutter analyze --no-pub"), ("pkg-test", PKG.strip())],
    "example": [("example-analyze", "cd packages/mobile/packages/ios_liquid_glass/example && flutter analyze --no-pub"), ("example-test", EXAMPLE.strip())],
    "app": [("app-analyze", "cd packages/mobile && flutter analyze --no-pub"), ("app-test", APP.strip())],
    "harness": [("harness", "cd packages/mobile && python3 -m unittest discover tool/glass_lab/harness/tests")],
}

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tasks import TASKS
out = []
for task in TASKS:
    n = task["n"]
    tag = f"t{n:02d}" if isinstance(n, int) else f"t{n}"
    out.append(f"### Task {n}: {task['title']}\n")
    out.append("**Files:**")
    for line in task["files"]:
        out.append(f"- {line}")
    out.append("")
    out.append(f"**Why.** {task['why']}\n")
    step = 1
    if task.get("tests"):
        t = task["tests"]
        out.append(f"- [ ] **Step {step}: Add the failing tests.**\n")
        out.append(f"<<PATCH {tag}-tests from={t['base']} to={t['head']} files=@tests>>\n")
        step += 1
        out.append(f"- [ ] **Step {step}: Run them and watch them fail.**\n")
        for label, command, before in task["runs"]:
            out.append(f"RUN[{tag}-{label}-red]: `{command}` => {before}\n")
            out.append(f"<<OUT {tag}-{label}-red>>\n")
        out.append(task.get("red_note", "Expected: each new test fails for the reason named in the patch (a missing symbol or a changed value); nothing else changes.") + "\n")
        step += 1
    p = task.get("impl")
    if p:
        out.append(f"- [ ] **Step {step}: {task.get('impl_title', 'Apply the implementation.')}**\n")
        out.append(f"<<PATCH {tag}-impl from={p['base']} to={p['head']} files={p.get('files', '@impl')}>>\n")
        step += 1
    for block in task.get("steps", []):
        out.append(block.replace("@@STEP@@", str(step)) + "\n")
        step += 1
    if task.get("runs"):
        out.append(f"- [ ] **Step {step}: Run the tests again and watch them pass.**\n")
        for label, command, before in task["runs"]:
            out.append(f"RUN[{tag}-{label}-green]: `{command}` => PASS\n")
            out.append(f"<<OUT {tag}-{label}-green>>\n")
        step += 1
    for label, command in task.get("checks", []):
        out.append(f"- [ ] **Step {step}: {task['check_titles'][label]}**\n")
        out.append(f"RUN[{tag}-{label}]: `{command}` => PASS\n")
        out.append(f"<<OUT {tag}-{label}>>\n")
        if label in task.get("check_notes", {}):
            out.append(task["check_notes"][label] + "\n")
        step += 1
    for gate in task.get("gates", []):
        out.append(f"- [ ] **Step {step}: Gate: {gate}.**\n")
        for label, command in GATES[gate]:
            out.append(f"RUN[{tag}-gate-{label}]: `{command}` => PASS\n")
            out.append(f"<<OUT {tag}-gate-{label}>>\n")
        step += 1
    if task.get("extra"):
        out.append(task["extra"] + "\n")
    out.append(f"- [ ] **Step {step}: Commit.**\n")
    out.append(f"```bash\n{task.get('add', 'git add -A packages')}\n" + f"git commit -m \"{task['commit']}\n\nCo-Authored-By: <the session's attribution line>\"\n```\n")
Path(sys.argv[1]).write_text("\n".join(out))
