import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const minutesArg = process.argv.indexOf("--minutes");
const minutes = minutesArg >= 0 ? Number(process.argv[minutesArg + 1]) : 30;

const server = await createServer({ configFile: path.join(benchDir, "vite.config.ts"), logLevel: "error" });
await server.listen(0);
const browser = await chromium.launch({ headless: true });
const samples = [];
process.stdout.write(`${JSON.stringify({ start: new Date().toISOString(), loadAvg: os.loadavg(), cpus: os.cpus().length })}\n`);
try {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/agent-session/index.html?fixture=claude-long-50k`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	const session = await page.context().newCDPSession(page);
	await session.send("Performance.enable");
	await page.evaluate(() => window.__agentSession.mountPanes(9, "parked"));
	await page.evaluate(() => window.__agentSession.startSoakFeed(64 * 1024));
	const task = async () => (await session.send("Performance.getMetrics")).metrics.find((m) => m.name === "TaskDuration").value;
	let last = await task();
	for (let minute = 1; minute <= minutes; minute += 1) {
		await page.waitForTimeout(60_000);
		const now = await task();
		await session.send("HeapProfiler.collectGarbage");
		const sample = {
			minute,
			loadAvg: os.loadavg(),
			taskDurationS: now - last,
			jsHeapUsedBytes: (await session.send("Runtime.getHeapUsage")).usedSize,
			domNodes: (await session.send("Memory.getDOMCounters")).nodes,
			...(await page.evaluate(() => window.__agentSession.paneMemory())),
		};
		last = now;
		samples.push(sample);
		process.stdout.write(`${JSON.stringify(sample)}\n`);
	}
} finally {
	process.stdout.write(`${JSON.stringify({ end: new Date().toISOString(), loadAvg: os.loadavg(), samples: samples.length })}\n`);
	await mkdir(path.join(benchDir, "results"), { recursive: true });
	await writeFile(path.join(benchDir, "results", `soak-${new Date().toISOString().replace(/[:.]/g, "-")}.json`), JSON.stringify(samples, null, "\t"));
	await browser.close();
	await server.close();
}
