import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const fixture = process.argv.includes("--fixture") ? process.argv[process.argv.indexOf("--fixture") + 1] : "claude-long-50k";

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	const result = await page.evaluate(async () => {
		const session = window.__agentSession;
		const total = session.renderableRowCount();
		const seen = new Map();
		const slow = [];
		let step = 0;
		const viewport = 450;
		let top = session.scrollHeight();
		let last = performance.now();
		while (top > 0) {
			top = Math.max(0, top - viewport);
			await session.setScrollTop(top);
			const now = performance.now();
			if (now - last > 50) slow.push(now - last);
			last = now;
			const byBlock = new Map();
			for (const { block, row } of session.visibleRows()) {
				if (!byBlock.has(block)) byBlock.set(block, []);
				byBlock.get(block).push(row);
				if (!seen.has(block)) seen.set(block, new Set());
				seen.get(block).add(row);
			}
			for (const [block, rows] of byBlock) {
				rows.sort((a, b) => a - b);
				for (let index = 1; index < rows.length; index += 1) {
					if (rows[index] !== rows[index - 1] + 1) throw new Error(`block ${block} rendered rows ${rows[index - 1]} and ${rows[index]} without ${rows[index - 1] + 1} at step ${step}`);
				}
			}
			step += 1;
		}
		let covered = 0;
		for (const rows of seen.values()) covered += rows.size;
		return { total, covered, steps: step, framesOver50ms: slow.length, worstFrameMs: slow.length ? Math.max(...slow) : 0 };
	});
	if (result.covered < result.total) throw new Error(`scrolling reached ${result.covered} of ${result.total} rows`);
	process.stdout.write(`${JSON.stringify({ fixture, ...result })}\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
