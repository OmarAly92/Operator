import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";
import { listFixtures, listProbes } from "./fixtures.mjs";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const baselinesDir = path.join(agentDir, "baselines");
const diffDir = path.join(benchDir, "results", "feel-diff");
const OFFSETS = [0, 0.25, 0.5, 0.75, 1];

const argv = process.argv.slice(2);
const record = argv.includes("--record");
const only = argv.includes("--fixture") ? argv[argv.indexOf("--fixture") + 1] : undefined;
const targets = [
	...listFixtures().map((name) => ({ name, dir: "fixtures" })),
	...listProbes().map((name) => ({ name, dir: "probes" })),
].filter((target) => !only || target.name === only);

const server = await createServer({ configFile, logLevel: "error" });
let browser;
let failures = 0;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	for (const { name: fixture, dir: fixtureDir } of targets) {
		const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
		await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}&dir=${fixtureDir}`);
		await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
		await page.evaluate(() => window.__agentSession.feedAll());
		await page.waitForTimeout(300);
		const dir = path.join(baselinesDir, fixture);
		await mkdir(dir, { recursive: true });
		for (const fraction of OFFSETS) {
			const name = `offset-${Math.round(fraction * 100)}.png`;
			await page.evaluate(async (f) => {
				const session = window.__agentSession;
				await session.setScrollTop(Math.round(session.scrollHeight() * f));
			}, fraction);
			await page.waitForTimeout(100);
			const shot = await page.screenshot({ type: "png", animations: "disabled", caret: "hide" });
			const file = path.join(dir, name);
			if (record || !existsSync(file)) {
				await writeFile(file, shot);
				process.stdout.write(`recorded ${fixture}/${name}\n`);
				continue;
			}
			const baseline = await readFile(file);
			if (Buffer.compare(baseline, shot) !== 0) {
				failures += 1;
				await mkdir(path.join(diffDir, fixture), { recursive: true });
				await writeFile(path.join(diffDir, fixture, name), shot);
				process.stderr.write(`DIFF ${fixture}/${name} (actual saved under bench/results/feel-diff)\n`);
			}
		}
		await page.close();
	}
	if (failures > 0) throw new Error(`${failures} screenshot(s) differ from the baseline`);
	process.stdout.write(record ? "recorded feel baselines\n" : "PASS feel gate: zero pixel diff\n");
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
