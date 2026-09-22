import { mkdir, writeFile } from "node:fs/promises";
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
if (!action) {
	process.stderr.write("usage: affordance-gate.mjs --action <hover|hint|redact>\n");
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
	const outDir = path.join(baselinesDir, `affordance-${action}`);
	await mkdir(outDir, { recursive: true });
	const shoot = async (name) => {
		await writeFile(path.join(outDir, `${name}.png`), await page.screenshot({ type: "png", animations: "disabled", caret: "hide" }));
		process.stdout.write(`side-by-side act-probe/affordance-${action}/${name}.png (compare with act-probe/offset-0.png)\n`);
	};
	const run = actions[action];
	if (!run) throw new Error(`unknown action ${action}`);
	const report = await run(page, shoot);
	process.stdout.write(`${JSON.stringify({ action, report })}\n`);
	await page.close();
} finally {
	await browser?.close();
	await server.close();
}
