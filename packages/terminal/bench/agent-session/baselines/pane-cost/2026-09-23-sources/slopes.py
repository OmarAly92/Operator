import json, sys

def slope(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)

for path in sys.argv[1:]:
    s = json.load(open(path))
    print(path, len(s), "samples")
    fields = {
        "wasmBytes": lambda r: r["wasmBytes"],
        "contentBytes": lambda r: r["cores"][0]["contentBytes"],
        "jsHeap": lambda r: r["jsHeapUsedBytes"],
        "domNodes": lambda r: r["domNodes"],
        "taskS": lambda r: r["taskDurationS"],
    }
    for name, f in fields.items():
        out = []
        for lo, hi in ((1, 30), (1, 9), (11, 30)):
            rs = [r for r in s if lo <= r["minute"] <= hi]
            out.append("%.3f" % slope([r["minute"] for r in rs], [f(r) for r in rs]))
        print(" ", name, out)
    same = all(len({(c["contentBytes"], c["rows"], c["styleEntries"]) for c in r["cores"]}) == 1 for r in s)
    print("  cores identical:", same)
    cap = next((r["minute"] for r in s if r["cores"][0]["rows"] >= 199999), None)
    print("  cap minute:", cap)
    wflat = next((r["minute"] for r in s if r["wasmBytes"] == s[-1]["wasmBytes"]), None)
    print("  wasm flat from:", wflat, "MiB", s[-1]["wasmBytes"] / 2**20)
    t = [r["taskDurationS"] for r in s]
    print("  task range", min(t), max(t), "mean", sum(t) / len(t))
    d = [r["domNodes"] for r in s]
    print("  dom", min(d), max(d), sorted(set(d)))
    la = [r["loadAvg"][0] for r in s]
    print("  load1 range", min(la), max(la))
    for m in (1, 3, 5, 7, 10, 20, 30):
        r = next(x for x in s if x["minute"] == m)
        print("   m", m, round(r["wasmBytes"] / 2**20, 1), r["cores"][0]["rows"], r["cores"][0]["contentBytes"], r["jsHeapUsedBytes"], r["domNodes"], round(r["taskDurationS"], 3), [round(x, 1) for x in r["loadAvg"]])
    st = [r["cores"][0]["styleEntries"] for r in s if r["minute"] >= 7]
    print("  styles at cap", min(st), max(st))
