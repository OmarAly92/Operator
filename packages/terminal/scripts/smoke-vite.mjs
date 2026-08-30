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
		await page.evaluate(() => window.scrollTo(0, 0));

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
			const node = document.querySelector("#terminal-smoke-root [data-testid='terminal-block-list']");
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

		await page.waitForSelector('[data-terminal-tier-one="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const tierOne = await page.evaluate(() => {
			const main = document.getElementById("terminal-tier-one-root");
			return {
				state: main?.dataset.lineEditorState ?? "",
				readOnly: main?.dataset.editorReadOnly ?? "",
				raw: main?.dataset.rawInput ?? "",
				blocks: main?.querySelectorAll("[data-terminal-block-id]").length ?? 0,
				recipe: main?.dataset.spawnRecipe ?? "",
			};
		});
		if (tierOne.state !== "unknown") {
			fail(`Tier-1 editor state must stay unknown, got ${tierOne.state}`);
		}
		if (tierOne.readOnly !== "true") {
			fail(`Tier-1 editor must render read-only, got ${tierOne.readOnly}`);
		}
		if (tierOne.raw !== "x\\r") {
			fail(`Tier-1 input must pass through as raw x\\r, got ${JSON.stringify(tierOne.raw)}`);
		}
		if (tierOne.blocks !== 1) {
			fail(`Tier-1 OSC 133 stream must render one block, got ${tierOne.blocks}`);
		}
		if (tierOne.recipe !== "zsh:osc133-only") {
			fail(`Tier-1 spawn recipe mismatch: ${tierOne.recipe}`);
		}

		await page.waitForSelector('[data-terminal-alt-shred="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const shred = await page.evaluate(() => {
			const main = document.getElementById("terminal-alt-root");
			if (!main) return null;
			return {
				before: main.dataset.terminalAltShredBefore ?? "",
				after: main.dataset.terminalAltShredAfter ?? "",
				beforeCount: main.dataset.terminalAltShredBeforeCount ?? "",
				afterCount: main.dataset.terminalAltShredAfterCount ?? "",
				surfaceHidden: main.dataset.terminalAltShredSurfaceHidden ?? "",
			};
		});
		if (!shred) {
			fail("alt-screen shred fixture did not mount #terminal-alt-root");
		}
		if (shred.beforeCount !== "1") {
			fail(`expected one block before alt screen, got ${shred.beforeCount}`);
		}
		if (shred.afterCount !== "1") {
			fail(
				`alt screen shredded the pre-existing block list (was ${shred.beforeCount}, now ${shred.afterCount})`,
			);
		}
		if (shred.before !== shred.after) {
			fail(
				`alt screen rewrote the pre-existing block ids: before "${shred.before}", after "${shred.after}"`,
			);
		}
		if (shred.surfaceHidden !== "true") {
			fail(
				`alt surface was still visible after the program left: hidden=${shred.surfaceHidden}`,
			);
		}

		await page.waitForSelector('[data-terminal-fallback="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const fallback = await page.evaluate(() => {
			const main = document.getElementById("terminal-fallback-root");
			const surface = main?.querySelector('[data-testid="terminal-fallback-surface"]');
			return {
				visible: main?.dataset.terminalFallbackVisible ?? "",
				surfacePresent: Boolean(surface),
				surfaceText: surface ? surface.textContent : "",
			};
		});
		if (fallback.surfacePresent !== true) {
			fail(
				"altScreenSurface slot was not rendered; the xterm fallback path has nothing to mount",
			);
		}
		if (fallback.visible !== "true") {
			fail(
				`altScreenSurface slot was hidden while altScreenActive=true; xterm fallback unreachable (visible=${fallback.visible})`,
			);
		}
		if (fallback.surfaceText !== "fallback-xterm-slot") {
			fail(
				`altScreenSurface slot did not render the host's child (got "${fallback.surfaceText}")`,
			);
		}

		await page.waitForSelector('[data-terminal-padding="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const padding = await page.evaluate(() => {
			const main = document.getElementById("terminal-padding-root");
			return {
				left: Number(main?.dataset.terminalPaddingInsetLeft ?? "-1"),
				top: Number(main?.dataset.terminalPaddingInsetTop ?? "-1"),
				right: Number(main?.dataset.terminalPaddingInsetRight ?? "-1"),
			};
		});
		if (padding.left !== 16 || padding.right !== 16) {
			fail(
				`the grid is not inset by Warp's 16px horizontally: left=${padding.left} right=${padding.right}. ` +
					"Padding belongs on .terminal-surface, never on the measured .terminal-host.",
			);
		}
		if (padding.top !== 8) {
			fail(`the grid is not inset by Warp's 8px vertically: top=${padding.top}`);
		}


		await page.waitForSelector('[data-terminal-alt-scroll="ready"]', {
			timeout: 15000,
			state: "attached",
		});
		const noScrollback = await page.evaluate(async () => {
			const main = document.getElementById("terminal-alt-scroll-root");
			const host = main ? main.querySelector(".terminal-host") : null;
			if (!host) return { hasHost: false };
			const before = host.scrollTop;
			host.scrollTop = 500;
			await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
			const after = host.scrollTop;
			return {
				hasHost: true,
				hostHeight: host.clientHeight,
				overflow: host.style.overflow,
				surfaceVisible: main && main.dataset ? main.dataset.terminalAltScrollSurfaceVisible : "",
				before,
				after,
			};
		});
		if (!noScrollback.hasHost) {
			fail("alt-scroll fixture did not mount a .terminal-host");
		}
		if (noScrollback.hostHeight <= 0) {
			fail(`alt-scroll host collapsed to ${noScrollback.hostHeight}px height`);
		}
		if (noScrollback.surfaceVisible !== "true") {
			fail(
				`alt-scroll fixture was not inside the alt screen when measured (visible=${noScrollback.surfaceVisible}); ` +
					"the no-scrollback check would be vacuous against the block list",
			);
		}
		if (noScrollback.overflow !== "hidden") {
			fail(
				`alt screen host did not set overflow:hidden (got "${noScrollback.overflow}"); ` +
					"the alt surface is allowed to scroll",
			);
		}
		if (noScrollback.after !== 0) {
			fail(
				`alt screen scrolled: scrollTop=${noScrollback.after} after a forced set to 500 (was ${noScrollback.before}); ` +
					"alternate buffer has scrollback, which §11 forbids",
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
