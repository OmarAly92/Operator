import re
from dataclasses import dataclass
from pathlib import Path

MATERIAL_DIR = Path(__file__).resolve().parents[3] / "packages" / "ios_liquid_glass" / "lib" / "src" / "material"
FIELD = re.compile(r"'(\w+)': (-?\d+(?:\.\d+)?(?:e-?\d+)?)")
APPEARANCES = ("dark", "light")
ROWS = ("regular", "clear", "tinted", "reduceTransparency", "increaseContrast")
ANCHORS = (44, 88, 200)
STYLES = ("soft", "hard", "automatic")
EDGE_PREFIX = "edge."


def material_order(key):
    appearance, row, anchor = key.split(".")
    return (APPEARANCES.index(appearance), ROWS.index(row), int(anchor))


def edge_order(key):
    appearance, style = key.split(".")
    return (APPEARANCES.index(appearance), STYLES.index(style))


@dataclass(frozen=True)
class Table:
    path: Path
    name: str
    key: str
    order: object


MATERIAL = Table(MATERIAL_DIR / "ios27.dart", "ios27Table", r"[a-zA-Z]+\.[a-zA-Z]+\.\d+", material_order)
SCROLL_EDGE = Table(MATERIAL_DIR / "ios27_scroll_edge.dart", "ios27ScrollEdgeTable", r"[a-zA-Z]+\.[a-zA-Z]+", edge_order)


def for_scene(scene_id):
    return SCROLL_EDGE if scene_id.startswith("material.edge.") else MATERIAL


def parse(text, table=MATERIAL):
    pattern = re.compile(rf"^\s*'({table.key})': \{{(.*)\}},\s*$")
    rows = {}
    for line in text.splitlines():
        match = pattern.match(line)
        if match:
            rows[match.group(1)] = {name: float(value) for name, value in FIELD.findall(match.group(2))}
    return rows


def number(value):
    text = f"{value:.4f}".rstrip("0")
    return text + "0" if text.endswith(".") else text


def format_table(rows, table=MATERIAL):
    lines = [f"const Map<String, Map<String, double>> {table.name} = {{"]
    for key in sorted(rows, key=table.order):
        body = ", ".join(f"'{name}': {number(value)}" for name, value in sorted(rows[key].items()))
        lines.append(f"  '{key}': {{{body}}},")
    lines.append("};")
    return "\n".join(lines) + "\n"


def read(path=None, table=MATERIAL):
    return parse(Path(path or table.path).read_text(), table)


def write(rows, path=None, table=MATERIAL):
    Path(path or table.path).write_text(format_table(rows, table))


def update(key, values, path=None, table=MATERIAL):
    rows = read(path, table)
    rows[key] = {**rows.get(key, {}), **values}
    write(rows, path, table)
    return rows
