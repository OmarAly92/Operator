import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const agentDir = path.dirname(fileURLToPath(import.meta.url));
const benchDir = path.resolve(agentDir, "..");
const configFile = path.join(benchDir, "vite.config.ts");
const outDir = path.join(agentDir, "baselines", "glyph-probe");
const MARKER_COLUMN = 39;
const NEEDED_PX = 1;

function verdict(px) {
	return Math.abs(px) >= NEEDED_PX ? "needed" : "not needed";
}

const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
	const features = process.argv.includes("--features") ? process.argv[process.argv.indexOf("--features") + 1] : "";
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=glyph-probe&dir=probes&features=${encodeURIComponent(features)}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	await page.evaluate(() => window.__agentSession.feedAll());
	await page.waitForTimeout(300);

	const layout = await page.evaluate((markerColumn) => {
		const session = window.__agentSession;
		const { cellWidth, cellHeight } = session.cellMetrics();
		const rows = [...document.querySelectorAll("[data-terminal-row]")];
		const rowStarting = (prefix) => rows.find((row) => (row.textContent ?? "").startsWith(prefix)) ?? null;
		const markerDrift = (prefix) => {
			const row = rowStarting(prefix);
			if (!row) throw new Error(`no row starts with ${prefix}`);
			const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
			for (let node = walker.nextNode(); node; node = walker.nextNode()) {
				const index = node.data.indexOf("|");
				if (index < 0) continue;
				const range = document.createRange();
				range.setStart(node, index);
				range.setEnd(node, index + 1);
				const left = range.getBoundingClientRect().left - row.getBoundingClientRect().left;
				return left - markerColumn * cellWidth;
			}
			throw new Error(`row ${prefix} has no | marker`);
		};
		const box = rowStarting("│ box");
		const rowsRow = rowStarting("│ rows");
		if (!box || !rowsRow) throw new Error("box rows missing");
		const boxRect = box.getBoundingClientRect();
		const rowsRect = rowsRow.getBoundingClientRect();
		return {
			cellWidth,
			cellHeight,
			wideDriftPx: markerDrift("wide:"),
			cjkDriftPx: markerDrift("cjk:"),
			seqDriftPx: markerDrift("seq:"),
			bar: { x: boxRect.left + cellWidth / 2, top: boxRect.top, bottom: rowsRect.bottom, left: boxRect.left },
		};
	}, MARKER_COLUMN);

	const clip = { x: Math.floor(layout.bar.left), y: Math.floor(layout.bar.top), width: Math.ceil(layout.cellWidth * 4), height: Math.ceil(layout.bar.bottom - layout.bar.top) };
	const shot = await page.screenshot({ type: "png", clip, animations: "disabled", caret: "hide" });
	const gap = await page.evaluate(async ({ png, clip, x }) => {
		const image = new Image();
		image.src = `data:image/png;base64,${png}`;
		await image.decode();
		const canvas = document.createElement("canvas");
		canvas.width = clip.width;
		canvas.height = clip.height;
		const context = canvas.getContext("2d");
		context.drawImage(image, 0, 0);
		const column = Math.round(x - clip.x);
		const { data } = context.getImageData(column, 0, 1, clip.height);
		const ink = [];
		for (let y = 0; y < clip.height; y += 1) {
			const r = data[y * 4], g = data[y * 4 + 1], b = data[y * 4 + 2];
			ink.push(Math.max(r, g, b) > 60);
		}
		const middle = Math.floor(clip.height / 2);
		let up = middle;
		while (up > 0 && !ink[up]) up -= 1;
		let down = middle;
		while (down < clip.height - 1 && !ink[down]) down += 1;
		return ink[middle] ? 0 : down - up - 1;
	}, { png: shot.toString("base64"), clip, x: layout.bar.x });

	const evidence = {
		measuredAt: new Date().toISOString(),
		features: features || "(all off)",
		cellWidth: layout.cellWidth,
		cellHeight: layout.cellHeight,
		boxGapPx: gap,
		wideDriftPx: Number(layout.wideDriftPx.toFixed(2)),
		cjkDriftPx: Number(layout.cjkDriftPx.toFixed(2)),
		seqDriftPx: Number(layout.seqDriftPx.toFixed(2)),
		boxDrawing: verdict(gap),
		widthCache: verdict(Math.max(Math.abs(layout.wideDriftPx), Math.abs(layout.cjkDriftPx))),
	};
	await mkdir(outDir, { recursive: true });
	const suffix = features ? `-${features.replace(/[^a-z0-9]+/gi, "_")}` : "";
	await writeFile(path.join(outDir, `box-zoom${suffix}.png`), shot);
	await writeFile(path.join(outDir, `EVIDENCE${suffix}.json`), JSON.stringify(evidence, null, "\t"));
	process.stdout.write(`${JSON.stringify(evidence)}\n`);
	await page.close();
} finally {
	await browser?.close();
	await server.close();
}
