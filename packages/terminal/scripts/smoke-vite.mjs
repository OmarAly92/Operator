#!/usr/bin/env node
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite";
import { chromium } from "playwright";

const require = createRequire(import.meta.url);
const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const configFile = resolve(packageRoot, "smoke", "vite.config.ts");
const smokeRoot = resolve(packageRoot, "smoke");

const REQUIRED_TEXT = "red caféplain";
const REQUIRED_ROWS = 2;
const REQUIRED_RUNS = 3;
const READY_SELECTOR = '[data-terminal-smoke="ready"]';

function fail(message) {
	process.stderr.write(`smoke-vite: ${message}\n`);
	process.exit(1);
}

async function main() {
	const playwrightPackage = require.resolve("playwright/package.json");
	void playwrightPackage;

	const server = await createServer({
		configFile,
		root: smokeRoot,
		server: {
			host: "127.0.0.1",
			port: 0,
			strictPort: false,
		},
		logLevel: "error",
	});
	await server.listen();

	const httpServer = server.httpServer;
	if (!httpServer) {
		await server.close();
		fail("vite did not expose an httpServer");
	}
	const address = httpServer.address();
	if (!address || typeof address === "string") {
		await server.close();
		fail(`vite did not return a numeric port (got ${JSON.stringify(address)})`);
	}
	const port = address.port;

	const browser = await chromium.launch({ headless: true });
	const context = await browser.newContext();
	const page = await context.newPage();

	const consoleErrors = [];
	const pageErrors = [];
	page.on("console", (message) => {
		if (message.type() === "error") {
			consoleErrors.push(message.text());
		}
	});
	page.on("pageerror", (error) => {
		pageErrors.push(error.message);
	});

	try {
		await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "load" });
		await page.waitForSelector(READY_SELECTOR, { timeout: 15000 });

		const rootHandle = await page.$("#terminal-smoke-root");
		if (!rootHandle) {
			fail("#terminal-smoke-root not present in DOM");
		}
		const rowCountAttr = await rootHandle.getAttribute("data-row-count");
		const runCountAttr = await rootHandle.getAttribute("data-run-count");
		if (rowCountAttr !== String(REQUIRED_ROWS)) {
			fail(`expected data-row-count="${REQUIRED_ROWS}", got "${rowCountAttr}"`);
		}
		if (runCountAttr !== String(REQUIRED_RUNS)) {
			fail(`expected data-run-count="${REQUIRED_RUNS}", got "${runCountAttr}"`);
		}

		const text = await page.evaluate(() => {
			const node = document.getElementById("terminal-smoke-root");
			return node ? node.textContent : "";
		});
		if (text !== REQUIRED_TEXT) {
			fail(`expected text "${REQUIRED_TEXT}", got "${text}"`);
		}

		const rowNodes = await page.locator("[data-terminal-row]").count();
		if (rowNodes !== REQUIRED_ROWS) {
			fail(`expected ${REQUIRED_ROWS} row nodes, got ${rowNodes}`);
		}
		const runNodes = await page.locator("[data-terminal-run]").count();
		if (runNodes !== REQUIRED_RUNS) {
			fail(`expected ${REQUIRED_RUNS} run nodes, got ${runNodes}`);
		}

		const resources = await page.evaluate(() => {
			const seen = new Set();
			performance.getEntriesByType("resource").forEach((entry) => {
				if (entry.name) {
					seen.add(entry.name);
				}
			});
			return Array.from(seen);
		});
		const wasmUrls = resources.filter((url) => url.endsWith(".wasm"));
		if (wasmUrls.length !== 1) {
			fail(
				`expected exactly 1 .wasm resource, got ${wasmUrls.length}: ${wasmUrls.join(", ")}`,
			);
		}

		if (consoleErrors.length > 0) {
			fail(`console errors: ${consoleErrors.join(" | ")}`);
		}
		if (pageErrors.length > 0) {
			fail(`page errors: ${pageErrors.join(" | ")}`);
		}

		process.stdout.write(
			`Vite smoke loaded vt_core_bg.wasm and painted ${REQUIRED_ROWS} rows / ${REQUIRED_RUNS} runs.\n`,
		);
	} finally {
		await context.close().catch(() => {});
		await browser.close().catch(() => {});
		await server.close().catch(() => {});
	}
}

main().catch((error) => {
	const message = error instanceof Error ? error.stack ?? error.message : String(error);
	fail(message);
});
