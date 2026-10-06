import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const baselinesDir = path.join(agentDir, "baselines", "act-probe");
const argv = process.argv.slice(2);
const action = argv.includes("--action") ? argv[argv.indexOf("--action") + 1] : undefined;
const outArg = argv.includes("--out") ? argv[argv.indexOf("--out") + 1] : undefined;
const compareDir = argv.includes("--compare") ? path.resolve(argv[argv.indexOf("--compare") + 1]) : undefined;
if (!action) {
	process.stderr.write("usage: affordance-gate.mjs --action <hover|hint|redact|select|find|marks> [--out <dir>] [--compare <dir>]\n");
	process.exit(2);
}

const actions = {
	async hover(page, shoot) {
		const report = [];
		for (const [name, row, cell, suffixes] of [
			["hover-url", 0, 10, null],
			["hover-osc8", 1, 8, null],
			["hover-wrapped", 3, 5, null],
			["hover-path", 0, 40, [".ts", ".go"]],
		]) {
			if (suffixes) await page.evaluate((list) => window.__agentSession.enablePathLinks(list), suffixes);
			await page.evaluate(([r, c]) => window.__agentSession.hoverCell(r, c), [row, cell]);
			await page.waitForTimeout(150);
			const link = await page.evaluate(() => window.__agentSession.hoveredLink());
			report.push([name, link?.kind ?? null, link?.uri ?? link?.path ?? null]);
			await shoot(name);
			await page.evaluate(() => window.__agentSession.clearHover());
		}
		return report;
	},
	async hint(page, shoot) {
		const count = await page.evaluate(() => window.__agentSession.hintBegin());
		await page.waitForTimeout(100);
		await shoot("hint-all");
		const labels = await page.evaluate(() => [...document.querySelectorAll(".terminal-hint-label")].map((node) => node.textContent));
		await page.evaluate(() => window.__agentSession.hintType(document.querySelector(".terminal-hint-label")?.textContent?.[0] ?? "a"));
		await page.waitForTimeout(100);
		await shoot("hint-narrowed");
		await page.evaluate(() => window.__agentSession.hintCancel());
		return [["hint-count", count, labels.slice(0, 8).join(",")]];
	},
	async redact(page, shoot) {
		await shoot("redact-off");
		await page.evaluate(() => window.__agentSession.setSecretPatterns([
			{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b" },
			{ source: "\\bAKIA[0-9A-Z]{16}\\b" },
		]));
		await page.waitForTimeout(150);
		await shoot("redact-on");
		const painted = await page.evaluate(() => document.querySelectorAll(".terminal-redaction").length);
		await page.evaluate(() => window.__agentSession.setSecretPatterns([]));
		return [["redact-boxes", painted, null]];
	},
	async select(page, shoot) {
		await page.evaluate(() => window.__agentSession.selectCells(0, 5, 2, 12));
		await shoot("select-rows");
		await page.evaluate(() => window.__agentSession.selectCells(3, 6, 3, 20));
		await shoot("select-one-row");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await shoot("select-cleared");
		return [];
	},
	async find(page, shoot) {
		const first = await page.evaluate(() => window.__agentSession.findShow("example", 0));
		await shoot("find-first");
		const next = await page.evaluate(() => window.__agentSession.findShow("example", 1));
		await shoot("find-next");
		await page.evaluate(() => window.__agentSession.selectCells(0, 2, 0, 30));
		await shoot("find-under-selection");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await page.evaluate(() => window.__agentSession.findHide());
		await shoot("find-closed");
		return [["find-count", first, next]];
	},
	async marks(page, shoot) {
		await shoot("marks-before");
		await page.evaluate(() => window.__agentSession.setMarks([
			{ pattern: "example", regex: false, colour: "color-mix(in srgb, var(--terminal-ansi-3) 40%, transparent)" },
			{ pattern: "TEXT", regex: false, colour: "color-mix(in srgb, var(--terminal-ansi-1) 40%, transparent)" },
			{ pattern: "\\d+", regex: true, colour: "color-mix(in srgb, var(--terminal-ansi-2) 40%, transparent)" },
		]));
		await shoot("marks-on");
		await page.evaluate(() => window.__agentSession.findShow("example", 1));
		await page.evaluate(() => window.__agentSession.selectCells(0, 2, 0, 30));
		await shoot("marks-overlap");
		await page.evaluate(() => window.__agentSession.selectionClear());
		await page.evaluate(() => window.__agentSession.findHide());
		await page.evaluate(() => window.__agentSession.setMarks([]));
		await shoot("marks-after");
		const painted = await page.evaluate(() => [...document.querySelectorAll("[data-terminal-row]")].filter((row) => row.style.backgroundImage !== "").length);
		return [["marks-rows-painted-after", painted, null]];
	},
};

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=act-probe&dir=probes`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	await page.waitForTimeout(300);
	const outDir = outArg ? path.resolve(outArg) : path.join(baselinesDir, `affordance-${action}`);
	await mkdir(outDir, { recursive: true });
	const shots = new Map();
	const differ = [];
	const shoot = async (name) => {
		const shot = await page.screenshot({ type: "png", animations: "disabled", caret: "hide" });
		shots.set(name, shot);
		await writeFile(path.join(outDir, `${name}.png`), shot);
		process.stdout.write(`side-by-side ${path.join(outDir, `${name}.png`)} (compare with act-probe/offset-0.png)\n`);
		if (!compareDir) return;
		const baseline = await readFile(path.join(compareDir, `${name}.png`));
		const same = Buffer.compare(baseline, shot) === 0;
		if (!same) differ.push(name);
		process.stdout.write(`${same ? "SAME" : "DIFF"} ${name}\n`);
	};
	const run = actions[action];
	if (!run) throw new Error(`unknown action ${action}`);
	const report = await run(page, shoot);
	if (shots.has("marks-before") && shots.has("marks-after")) {
		report.push(["marks-after-equals-before", Buffer.compare(shots.get("marks-before"), shots.get("marks-after")) === 0, null]);
	}
	process.stdout.write(`${JSON.stringify({ action, report })}\n`);
	await page.close();
	if (differ.length > 0) throw new Error(`${differ.length} screenshot(s) differ from ${compareDir}: ${differ.join(", ")}`);
	if (compareDir) process.stdout.write(`PASS ${action}: every screenshot matches ${compareDir}\n`);
} finally {
	await browser?.close();
	await server.close();
}
