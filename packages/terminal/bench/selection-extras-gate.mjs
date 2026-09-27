import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const configFile = fileURLToPath(new URL("./vite.config.ts", import.meta.url));
const copyChord = process.platform === "darwin" ? "Meta+c" : "Control+Shift+c";

async function copy(page) {
	const before = await page.evaluate(() => window.__gate.copied.length);
	await page.keyboard.press(copyChord);
	await page.waitForFunction((count) => window.__gate.copied.length > count, before, { timeout: 5000 });
	return page.evaluate(() => window.__gate.copied.at(-1) ?? "");
}

function visibleRows(page) {
	return page.evaluate(() =>
		[...document.querySelectorAll("[data-terminal-row]")]
			.filter((element) => element.getClientRects().length > 0)
			.map((element) => {
				const box = element.getBoundingClientRect();
				return { row: Number(element.dataset.terminalRow), text: element.textContent ?? "", left: box.left, top: box.top, bottom: box.bottom, width: box.width };
			})
			.filter((row) => row.top > 60 && row.bottom < 840)
			.sort((a, b) => a.row - b.row),
	);
}

const middle = (row) => (row.top + row.bottom) / 2;

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
	const cell = await page.evaluate(() => {
		const run = [...document.querySelectorAll("[data-terminal-run]")].find((element) => /^[ -~]{10,}$/u.test(element.textContent ?? ""));
		if (!run) throw new Error("no ASCII run to measure a cell from");
		return run.getBoundingClientRect().width / (run.textContent ?? "").length;
	});

	await page.mouse.move(800, 450);
	await page.mouse.wheel(0, -100000);
	await page.waitForTimeout(300);
	const first = (await visibleRows(page)).find((row) => row.text.startsWith("Thinking through step"));
	if (!first) throw new Error("no 'Thinking through step' row on screen at the top");
	await page.mouse.click(first.left + 2, middle(first));
	await page.mouse.move(800, 450);
	await page.mouse.wheel(0, 100000);
	await page.waitForTimeout(300);
	const bottomRows = await visibleRows(page);
	if (bottomRows.some((row) => row.row === first.row)) throw new Error("the clicked row is still on screen, so the Shift+click would not cross rows scrolled out of view");
	const last = [...bottomRows].reverse().find((row) => row.text.startsWith("Edited file"));
	if (!last) throw new Error("no 'Edited file' row on screen at the bottom");
	await page.keyboard.down("Shift");
	await page.mouse.click(last.left + last.width - 4, middle(last));
	await page.keyboard.up("Shift");
	const extended = await copy(page);
	if (!extended.startsWith(first.text.trimEnd()) || !extended.endsWith(last.text.trimEnd())) {
		throw new Error(`Shift+click copied ${JSON.stringify(extended.slice(0, 80))}…${JSON.stringify(extended.slice(-80))}`);
	}
	const extendedLines = extended.split("\n").length;
	if (extendedLines < 40) throw new Error(`Shift+click copied ${extendedLines} lines, expected at least 40`);
	process.stdout.write(`PASS shift-click copied ${extendedLines} lines from row ${first.row} to row ${last.row}\n`);

	const textRows = (await visibleRows(page)).filter((row) => row.text.trim().length > 12);
	if (textRows.length < 8) throw new Error(`only ${textRows.length} text rows on screen for the rectangle`);
	const top = textRows[textRows.length - 8];
	const bottom = textRows[textRows.length - 5];
	const from = { x: top.left + cell * 2 + 1, y: middle(top) };
	const to = { x: top.left + cell * 12 - 1, y: middle(bottom) };
	await page.keyboard.down("Alt");
	await page.mouse.move(from.x, from.y);
	await page.mouse.down();
	for (let step = 1; step <= 20; step += 1) await page.mouse.move(from.x + ((to.x - from.x) * step) / 20, from.y + ((to.y - from.y) * step) / 20);
	await page.mouse.up();
	await page.keyboard.up("Alt");
	const expected = await page.evaluate(([a, b]) => {
		const byRow = new Map();
		for (const element of document.querySelectorAll("[data-terminal-row]")) {
			if (element.getClientRects().length === 0) continue;
			const row = Number(element.dataset.terminalRow);
			if (row >= a && row <= b) byRow.set(row, (element.textContent ?? "").slice(2, 12).replace(/ +$/u, ""));
		}
		return [...byRow.entries()].sort((x, y) => x[0] - y[0]).map(([, text]) => text);
	}, [top.row, bottom.row]);
	const boxed = await copy(page);
	if (boxed !== expected.join("\n")) throw new Error(`Alt-drag copied ${JSON.stringify(boxed)}, expected ${JSON.stringify(expected.join("\n"))}`);
	const painted = await page.evaluate(() => document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]').length);
	if (painted !== expected.length) throw new Error(`Alt-drag painted ${painted} rows, expected ${expected.length}`);
	process.stdout.write(`PASS alt-drag copied ${expected.length} slices of cells 2-12\n`);

	const target = [...(await visibleRows(page))].reverse().find((row) => /^Edited file src\/module-\d+\.ts/u.test(row.text));
	if (!target) throw new Error("no 'Edited file src/module-N.ts' row on screen");
	const word = target.text.split(" ")[2];
	await page.mouse.dblclick(target.left + cell * 15 + 1, middle(target));
	const before = await copy(page);
	if (before !== word) throw new Error(`double-click copied ${JSON.stringify(before)}, expected ${JSON.stringify(word)}`);
	await page.setViewportSize({ width: 260, height: 900 });
	await page.waitForTimeout(600);
	const after = await copy(page);
	if (after !== word) throw new Error(`after the resize the selection copied ${JSON.stringify(after)}, expected ${JSON.stringify(word)}`);
	const paintedText = await page.evaluate(() => [...document.querySelectorAll('[data-terminal-row][style*="terminal-selection"]')].map((element) => element.textContent ?? "").join("\n"));
	if (!paintedText.includes(word)) throw new Error(`after the resize the painted rows read ${JSON.stringify(paintedText)}`);
	process.stdout.write(`PASS ${word} stayed selected across a resize to 260 px\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
