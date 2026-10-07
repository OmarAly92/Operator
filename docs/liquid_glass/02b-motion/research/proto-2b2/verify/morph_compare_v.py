import sys
from pathlib import Path

source = (Path(__file__).resolve().parent.parent / "morph-flutter" / "morph_compare.py").read_text()
patched = source.replace('"start": round(entry["start"], 1)', '"start": round(entry["start"], 1) if "start" in entry else None')
if patched == source:
    raise SystemExit("morph_compare.py changed: the start patch no longer applies")
exec(compile(patched, "morph_compare.py (start optional)", "exec"))
