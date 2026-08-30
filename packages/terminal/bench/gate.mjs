import { readFile, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import scenarios from "./scenarios.json" with { type: "json" };

const benchDir = dirname(fileURLToPath(import.meta.url));

/**
 * The most recent measurement of each scenario, which is not the same as the
 * most recent file: a run names one scenario at a time, so the newest file
 * holds only whatever was measured last.
 */
async function latestResult(renderer) {
	const dir = join(benchDir, "results");
	const files = (await readdir(dir)).filter((f) => f.endsWith(`-${renderer}.json`)).sort().reverse();
	if (files.length === 0) throw new Error(`no recorded results for ${renderer}; run bench:terminal first`);
	const merged = { scenarios: {}, measuredAt: {} };
	for (const file of files) {
		const parsed = JSON.parse(await readFile(join(dir, file), "utf8"));
		for (const [name, scenario] of Object.entries(parsed.scenarios ?? {})) {
			if (merged.scenarios[name]) continue;
			merged.scenarios[name] = scenario;
			merged.measuredAt[name] = file;
		}
	}
	return merged;
}

async function baseline() {
	const dir = join(benchDir, "baselines");
	const files = (await readdir(dir)).filter((f) => f.endsWith("-xterm.json"));
	if (files.length !== 1) throw new Error(`expected exactly one xterm baseline, found ${files.length}`);
	return JSON.parse(await readFile(join(dir, files[0]), "utf8"));
}

const RULES = [
	{ scenario: "vtebench", compare: "at-least", factor: 0.9 },
	{ scenario: "large-output", compare: "at-least", factor: 1 },
	{ scenario: "input-latency", compare: "at-most", factor: 1 },
	{ scenario: "input-latency-owned", compare: "budget" },
];

const rows = [];
let failed = 0;
const base = await baseline();
const dom = await latestResult("dom");

for (const rule of RULES) {
	const measured = dom.scenarios[rule.scenario];
	if (!measured) {
		rows.push([rule.scenario, "MISSING", "-", "not measured"]);
		failed += 1;
		continue;
	}
	if (rule.compare === "budget") {
		const budget = scenarios[rule.scenario].maxP95Milliseconds;
		const ok = measured.p95 <= budget;
		if (!ok) failed += 1;
		rows.push([rule.scenario, `p95 ${measured.p95.toFixed(2)}ms`, `budget ${budget}ms`, ok ? "pass" : "FAIL"]);
		continue;
	}
	const reference = base.scenarios[rule.scenario];
	if (!reference) throw new Error(`baseline has no ${rule.scenario}`);
	const mine = rule.compare === "at-most" ? measured.p95 : measured.median;
	const theirs = rule.compare === "at-most" ? reference.p95 : reference.median;
	const threshold = theirs * rule.factor;
	const ok = rule.compare === "at-most" ? mine <= threshold : mine >= threshold;
	if (!ok) failed += 1;
	rows.push([
		rule.scenario,
		`${mine.toFixed(2)}`,
		`${rule.compare === "at-most" ? "<=" : ">="} ${threshold.toFixed(2)} (xterm ${theirs.toFixed(2)})`,
		ok ? "pass" : "FAIL",
	]);
}

const width = rows.reduce((w, r) => Math.max(w, r[0].length), 8);
for (const [name, mine, bound, verdict] of rows) {
	process.stdout.write(`${name.padEnd(width)}  ${mine.padEnd(18)} ${bound.padEnd(34)} ${verdict}\n`);
}
if (failed > 0) {
	process.stderr.write(`\nperf gate FAILED: ${failed} of ${RULES.length} scenarios\n`);
	process.exitCode = 1;
} else {
	process.stdout.write("\nperf gate passed\n");
}
