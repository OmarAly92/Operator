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
	await page.goto(`http://127.0.0.1:${address.port}/scroll.html`);
	await page.waitForFunction(() => window.__terminalScrollReady === true, undefined, { timeout: 15000 });
	const result = await page.evaluate(async () => {
		const host = document.querySelector(".terminal-host");
		if (!(host instanceof HTMLElement)) throw new Error("scroll host is missing");
		const frames = [];
		let last = performance.now();
		const maximum = host.scrollHeight - host.clientHeight;
		for (let step = 0; step < 120; step += 1) {
			host.scrollTop = maximum * (step / 119);
			host.dispatchEvent(new Event("scroll"));
			await new Promise((resolve) => requestAnimationFrame(resolve));
			const now = performance.now();
			frames.push(now - last);
			last = now;
		}
		frames.sort((left, right) => left - right);
		return {
			blocks: document.querySelectorAll("[data-terminal-block-id]").length,
			totalBlocks: window.__terminalScrollBlockCount,
			p95: frames[Math.floor(frames.length * 0.95)],
		};
	});
	if (result.totalBlocks !== 50000) throw new Error(`expected 50,000 decoded blocks, got ${result.totalBlocks}`);
	if (result.blocks >= 50000) throw new Error(`virtualization rendered ${result.blocks} blocks`);
	if (result.p95 >= 16.7) throw new Error(`50,000-block scroll p95 ${result.p95.toFixed(2)}ms exceeds 16.7ms`);
	process.stdout.write(`50,000-block scroll p95 ${result.p95.toFixed(2)}ms with ${result.blocks} live blocks.\n`);
} finally {
	await browser?.close();
	await server.close();
}
