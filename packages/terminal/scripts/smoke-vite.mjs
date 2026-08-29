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
	throw new Error(message);
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

		const geometry = await page.evaluate(() => {
			const host = document.querySelector("#terminal-smoke-root .terminal-host");
			const row = document.querySelector("#terminal-smoke-root [data-terminal-row]");
			const rect = (el) => (el ? el.getBoundingClientRect() : null);
			const hostRect = rect(host);
			const rowRect = rect(row);
			return {
				hasHost: Boolean(host),
				hostHeight: hostRect ? hostRect.height : 0,
				hostWidth: hostRect ? hostRect.width : 0,
				rowHeight: rowRect ? rowRect.height : 0,
				rowVisible: rowRect
					? rowRect.height > 0 &&
						rowRect.width > 0 &&
						rowRect.top < window.innerHeight &&
						rowRect.bottom > 0
					: false,
			};
		});
		if (!geometry.hasHost) {
			fail("no .terminal-host element in the DOM");
		}
		if (geometry.hostHeight <= 0 || geometry.hostWidth <= 0) {
			fail(
				`terminal host collapsed to ${geometry.hostWidth}x${geometry.hostHeight}; ` +
					"rows exist in the DOM but nothing is on screen",
			);
		}
		if (!geometry.rowVisible) {
			fail(
				`first row is not visible on screen (height ${geometry.rowHeight})`,
			);
		}

		const rowNodes = await page.locator("#terminal-smoke-root [data-terminal-row]").count();
		if (rowNodes !== REQUIRED_ROWS) {
			fail(`expected ${REQUIRED_ROWS} row nodes, got ${rowNodes}`);
		}
		const runNodes = await page.locator("#terminal-smoke-root [data-terminal-run]").count();
		if (runNodes !== REQUIRED_RUNS) {
			fail(`expected ${REQUIRED_RUNS} run nodes, got ${runNodes}`);
		}

		await page.waitForSelector('[data-terminal-follow="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const follow = await page.evaluate(() => {
			const main = document.getElementById("terminal-follow-root");
			const host = main ? main.querySelector(".terminal-host") : null;
			if (!host) {
				return { hasHost: false };
			}
			const rows = Array.from(host.querySelectorAll("[data-terminal-row]"));
			const last = rows.length > 0 ? rows[rows.length - 1] : null;
			const lastWithText = [...rows].reverse().find((row) => row.textContent !== "") ?? null;
			const hostRect = host.getBoundingClientRect();
			const lastRect = last ? last.getBoundingClientRect() : null;
			return {
				hasHost: true,
				scrollTop: host.scrollTop,
				scrollHeight: host.scrollHeight,
				clientHeight: host.clientHeight,
				renderedRows: rows.length,
				lastText: lastWithText ? lastWithText.textContent : "",
				lastRowOnScreen: lastRect
					? lastRect.bottom <= hostRect.bottom + 2 && lastRect.bottom > hostRect.top
					: false,
			};
		});
		if (!follow.hasHost) {
			fail("follow fixture did not mount a .terminal-host");
		}
		if (follow.scrollHeight <= follow.clientHeight) {
			fail(
				`follow fixture did not overflow (scrollHeight ${follow.scrollHeight}, ` +
					`clientHeight ${follow.clientHeight}); the follow assertion would be vacuous`,
			);
		}
		const expectedScrollHeight = follow.clientHeight * 8;
		if (follow.scrollHeight < expectedScrollHeight) {
			fail(
				`follow fixture scrollHeight is ${follow.scrollHeight} for 500 lines; the block ` +
					"is not reserving space for its off-screen rows, so scrollback is unreachable",
			);
		}
		const distanceFromBottom = follow.scrollHeight - follow.scrollTop - follow.clientHeight;
		if (distanceFromBottom > 4) {
			fail(
				`terminal did not follow its output: ${distanceFromBottom}px from the bottom ` +
					`(scrollTop ${follow.scrollTop} of ${follow.scrollHeight})`,
			);
		}
		if (follow.lastText !== "line-500") {
			fail(
				`expected the newest non-empty row to be "line-500", got "${follow.lastText}"`,
			);
		}
		if (!follow.lastRowOnScreen) {
			fail("the newest row is not inside the visible viewport");
		}
		if (follow.renderedRows >= 500) {
			fail(
				`follow fixture rendered ${follow.renderedRows} rows; virtualization should ` +
					"keep this near the viewport size",
			);
		}

		await page.evaluate(() => {
			const host = document.querySelector("#terminal-follow-root .terminal-host");
			if (host) host.scrollTop = 0;
		});
		await page.evaluate(
			() =>
				new Promise((resolve) => {
					requestAnimationFrame(() => requestAnimationFrame(resolve));
				}),
		);
		const scrolledBack = await page.evaluate(() => {
			const host = document.querySelector("#terminal-follow-root .terminal-host");
			const rows = host ? Array.from(host.querySelectorAll("[data-terminal-row]")) : [];
			const firstWithText = rows.find((row) => row.textContent !== "");
			return {
				scrollTop: host ? host.scrollTop : -1,
				firstText: firstWithText ? firstWithText.textContent : "",
				renderedRows: rows.length,
			};
		});
		if (scrolledBack.firstText !== "line-1") {
			fail(
				`scrolling to the top showed "${scrolledBack.firstText}" instead of "line-1"; ` +
					"the oldest output is unreachable",
			);
		}
		if (scrolledBack.renderedRows >= 500) {
			fail(
				`scrolled-back view rendered ${scrolledBack.renderedRows} rows; virtualization ` +
					"should keep this near the viewport size",
			);
		}

		const held = await page.evaluate(async () => {
			const host = document.querySelector("#terminal-follow-root .terminal-host");
			if (!host) return { ok: false };
			const target = Math.round(host.scrollHeight / 2);
			host.scrollTop = target;
			await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
			const afterScroll = host.scrollTop;
			for (let i = 0; i < 6; i += 1) {
				window.dispatchEvent(new Event("resize"));
				host.dispatchEvent(new Event("scroll"));
				await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
			}
			return { ok: true, target, afterScroll, afterRepaints: host.scrollTop };
		});
		if (!held.ok) {
			fail("follow fixture host vanished before the scroll-hold check");
		}
		if (Math.abs(held.afterRepaints - held.afterScroll) > 2) {
			fail(
				`scroll position drifted across repaints: parked at ${held.afterScroll}, ` +
					`ended at ${held.afterRepaints}; scrolling back through history fights the user`,
			);
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
			`Vite smoke loaded vt_core_bg.wasm and painted ${REQUIRED_ROWS} rows / ${REQUIRED_RUNS} runs ` +
				`in a ${Math.round(geometry.hostWidth)}x${Math.round(geometry.hostHeight)} host; followed 500 lines to the bottom with ${follow.renderedRows} rows in the DOM.\n`,
		);
	} finally {
		await context.close().catch(() => {});
		await browser.close().catch(() => {});
		await server.close().catch(() => {});
	}
}

main().catch((error) => {
	const message = error instanceof Error ? error.message : String(error);
	process.stderr.write(`smoke-vite: ${message}\n`);
	process.exitCode = 1;
});
