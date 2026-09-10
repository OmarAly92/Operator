import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const configFile = fileURLToPath(new URL("./vite.config.ts", import.meta.url));

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const address = server.httpServer?.address();
	if (!address || typeof address === "string") throw new Error("Vite did not bind a loopback port");
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${address.port}/select.html`);
	await page.waitForFunction(() => window.__gateReady === true, undefined, { timeout: 15000 });

	await page.evaluate(() => window.__gate.startSpinner());

	const start = await page.evaluate(() => {
		const row = [...document.querySelectorAll("[data-terminal-row]")].find((el) => {
			const box = el.getBoundingClientRect();
			return box.top > 60 && box.bottom < 840 && (el.textContent ?? "").trim().length > 10;
		});
		if (!row) throw new Error("no transcript row is on screen to start the drag from");
		const box = row.getBoundingClientRect();
		return { x: Math.round(box.left + 8), y: Math.round(box.top + box.height / 2) };
	});
	const end = { x: 900, y: 560 };
	const steps = 60;

	await page.mouse.click(start.x, start.y);

	await page.mouse.move(start.x, start.y);
	await page.mouse.down();
	for (let step = 1; step <= steps; step += 1) {
		await page.mouse.move(
			start.x + ((end.x - start.x) * step) / steps,
			start.y + ((end.y - start.y) * step) / steps,
		);
	}
	await page.mouse.up();

	await page.waitForTimeout(500);

	await page.keyboard.press("Meta+c");

	const result = await page.evaluate(() => ({
		copiedLength: window.__gate.copied[0]?.length ?? 0,
		selectedRows: document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]').length,
		tickCount: window.__gate.tickCount,
	}));

	await page.evaluate(() => window.__gate.stopSpinner());

	if (!(result.copiedLength > 100)) {
		throw new Error(`copied text was only ${result.copiedLength} characters, expected > 100`);
	}
	if (!(result.selectedRows > 5)) {
		throw new Error(`only ${result.selectedRows} rows carried the selection band, expected > 5`);
	}

	process.stdout.write(`PASS selection survived ${result.tickCount} repaints\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
