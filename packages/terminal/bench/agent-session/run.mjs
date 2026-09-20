import { spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";
import { frameBoundaries, listFixtures, loadFixture } from "./fixtures.mjs";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const resultsDir = path.join(benchDir, "results");

function parseArgs(argv) {
	const out = { fixture: undefined, gate: false };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--fixture") out.fixture = argv[++index];
		else if (argv[index] === "--gate") out.gate = true;
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	return out;
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted.length === 0 ? null : sorted[Math.floor(sorted.length / 2)];
}

async function openPage(browser, port, fixture) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=${fixture}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	return page;
}

async function feedCostAt(page, rows) {
	const reached = await page.evaluate((target) => window.__agentSession.feedUntilRows(target), rows);
	if (reached < rows) return { rows, reached, medianMs: null };
	const samples = await page.evaluate(() => {
		const out = [];
		for (let index = 0; index < 20; index += 1) {
			const cost = window.__agentSession.feedNext(4096);
			if (cost === 0) break;
			out.push(cost);
		}
		return out;
	});
	return { rows, reached, medianMs: median(samples), samples: samples.length };
}

async function spinnerPaints(page) {
	await page.evaluate(() => window.__agentSession.resetCounters());
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	await page.waitForTimeout(200);
	return page.evaluate(() => ({
		paints: window.__agentSession.paintCount(),
		addedNodes: window.__agentSession.addedNodes(),
	}));
}

async function feedSyncCostAt(page, rows) {
	const reached = await page.evaluate((target) => window.__agentSession.feedUntilRows(target), rows);
	if (reached < rows) return { rows, reached, medianMs: null };
	const samples = await page.evaluate(() => {
		const out = [];
		for (let index = 0; index < 20; index += 1) {
			const cost = window.__agentSession.feedNextSynced(4096);
			if (cost === 0) break;
			out.push(cost);
		}
		return out;
	});
	return { rows, reached, medianMs: median(samples), samples: samples.length };
}

async function idlePanes(page) {
	const session = await page.context().newCDPSession(page);
	await session.send("Performance.enable");
	await page.evaluate(() => window.__agentSession.mountPanes(9));
	const before = (await session.send("Performance.getMetrics")).metrics.find((m) => m.name === "TaskDuration").value;
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	const after = (await session.send("Performance.getMetrics")).metrics.find((m) => m.name === "TaskDuration").value;
	return { panes: 10, seconds: 10, taskDurationS: after - before };
}

async function selectionRepaint(page) {
	await page.evaluate(() => window.__agentSession.feedFrames(5, 20));
	const rowsRepainted = await page.evaluate(() => window.__agentSession.extendSelectionByOneRow());
	return { rowsRepainted };
}

async function tornPaints(page, recording) {
	const ends = frameBoundaries(recording);
	const states = await page.evaluate((frameEnds) => {
		const session = window.__agentSession;
		let tornStates = 0;
		let start = session.fed;
		for (const end of frameEnds) {
			if (end <= start) continue;
			let last = session.modelHash();
			for (let at = start; at < end; at += 1) {
				session.feedChunk(at, at + 1);
				const hash = session.modelHash();
				if (hash !== last) {
					if (at + 1 < end) tornStates += 1;
					last = hash;
				}
			}
			start = end;
		}
		return { frames: frameEnds.length, tornStates };
	}, ends);
	return states;
}

async function paintsPerFrame(page, recording) {
	const ends = frameBoundaries(recording);
	return page.evaluate(async (frameEnds) => {
		const session = window.__agentSession;
		const frame = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
		const settle = async () => {
			await frame();
			await frame();
		};
		let tornPaints = 0;
		let multiPaintFrames = 0;
		let start = session.fed;
		for (const end of frameEnds) {
			if (end <= start) continue;
			await settle();
			const before = session.textHash();
			const cuts = [start + Math.floor((end - start) / 3), start + Math.floor((2 * (end - start)) / 3), end];
			const seen = new Set();
			let from = start;
			for (const cut of cuts) {
				if (cut > from) session.feedChunk(from, cut);
				from = cut;
				await frame();
				seen.add(session.textHash());
			}
			const after = session.textHash();
			for (const hash of seen) if (hash !== before && hash !== after) tornPaints += 1;
			const distinct = [...seen].filter((hash) => hash !== before).length;
			if (distinct > 1) multiPaintFrames += 1;
			start = end;
		}
		return { tornPaints, multiPaintFrames };
	}, ends);
}

async function longTask2MiB(page) {
	await page.evaluate(() => window.__agentSession.resetCounters());
	const feedMs = await page.evaluate(() => window.__agentSession.feedNext(2 * 1024 * 1024));
	await page.waitForTimeout(500);
	const syncTasks = await page.evaluate(() => window.__agentSession.longTasks());
	await page.evaluate(() => window.__agentSession.resetCounters());
	const queued = await page.evaluate(async () => {
		const session = window.__agentSession;
		const core = session.core();
		const start = session.fed;
		const end = Math.min(session.fixture.bytes, start + 2 * 1024 * 1024);
		const bytes = await (await fetch(`/agent-session/fixtures/${session.fixture.name}/recording`)).arrayBuffer();
		const chunk = new Uint8Array(bytes).subarray(start, end);
		const began = performance.now();
		core.enqueue(chunk);
		let frames = 0;
		let previous = began;
		let longestFrameMs = 0;
		while (core.hasBacklog()) {
			await new Promise((resolve) => requestAnimationFrame(resolve));
			frames += 1;
			const at = performance.now();
			longestFrameMs = Math.max(longestFrameMs, at - previous);
			previous = at;
		}
		const totalMs = performance.now() - began;
		return { frames, totalMs, longestFrameMs, meanFrameMs: frames === 0 ? 0 : totalMs / frames };
	});
	await page.waitForTimeout(500);
	const queuedTasks = await page.evaluate(() => window.__agentSession.longTasks());
	return {
		feedMs,
		longestTaskMs: syncTasks.length ? Math.max(...syncTasks) : null,
		queued: { ...queued, longestTaskMs: queuedTasks.length ? Math.max(...queuedTasks) : null, longTasks: queuedTasks.length },
	};
}

async function reopenReport(page, fixtureName) {
	const fixtureDir = path.join(benchDir, "agent-session", "fixtures", fixtureName);
	const replayOut = path.join(resultsDir, `${fixtureName}-replay.bin`);
	await mkdir(resultsDir, { recursive: true });
	const backend = path.resolve(benchDir, "../../../backend");
	const run = spawnSync("go", ["test", "./internal/adapters/runtime/ptyhost/vtwasm/", "-run", "TestAgentSessionReplayReport", "-v", "-count=1"], {
		cwd: backend,
		env: { ...process.env, OPERATOR_AGENT_FIXTURE: fixtureDir, OPERATOR_AGENT_REPLAY_OUT: replayOut },
		encoding: "utf8",
	});
	const line = run.stdout.split("\n").find((entry) => entry.includes("REPORT "));
	if (!line) throw new Error(`reopen report missing:\n${run.stdout}\n${run.stderr}`);
	const report = JSON.parse(line.slice(line.indexOf("REPORT ") + 7));
	const replay = new Uint8Array(await readFile(replayOut));
	const firstPaintMs = await page.evaluate(async (bytes) => {
		const session = window.__agentSession;
		const start = performance.now();
		session.resetCounters();
		session.core().feed(new Uint8Array(bytes));
		while (session.paintCount() === 0) await new Promise((resolve) => requestAnimationFrame(resolve));
		return performance.now() - start;
	}, Array.from(replay));
	return { ...report, firstPaintMs };
}

async function main() {
	const args = parseArgs(process.argv.slice(2));
	const fixtures = args.fixture ? [args.fixture] : listFixtures();
	const server = await createServer({ configFile, logLevel: "error" });
	let browser;
	const report = { measuredAt: new Date().toISOString(), fixtures: {} };
	try {
		await server.listen(0);
		const port = server.httpServer.address().port;
		browser = await chromium.launch({ headless: true });
		for (const name of fixtures) {
			const fixture = await loadFixture(name);
			const rows = {};
			if (name === "claude-spinner-10s") {
				const page = await openPage(browser, port, name);
				rows.spinner = await spinnerPaints(page);
				rows.spinner.rowNodesAdded = await page.evaluate(() => window.__agentSession.rowNodesAdded());
				await page.close();
				const tearPage = await openPage(browser, port, name);
				const states = await tornPaints(tearPage, fixture.recording);
				await tearPage.close();
				const paintPage = await openPage(browser, port, name);
				rows.tearing = { ...states, ...(await paintsPerFrame(paintPage, fixture.recording)) };
				await paintPage.close();
				const idlePage = await openPage(browser, port, name);
				rows.idlePanes = await idlePanes(idlePage);
				await idlePage.close();
				const selectionPage = await openPage(browser, port, name);
				rows.selectionRepaint = await selectionRepaint(selectionPage);
				await selectionPage.close();
			} else {
				const page = await openPage(browser, port, name);
				rows.feedCost = [];
				for (const target of [1000, 5000, 50000]) rows.feedCost.push(await feedCostAt(page, target));
				await page.evaluate(() => window.__agentSession.feedAll());
				rows.rows = await page.evaluate(() => window.__agentSession.rowCount());
				rows.rendererMemoryBytes = await page.evaluate(() => window.__agentSession.memoryBytes());
				await page.close();
				const feedSyncPage = await openPage(browser, port, name);
				rows.feedSyncCost = [];
				for (const target of [1000, 5000, 50000]) rows.feedSyncCost.push(await feedSyncCostAt(feedSyncPage, target));
				await feedSyncPage.close();
				const longTaskPage = await openPage(browser, port, name);
				rows.longTask = await longTask2MiB(longTaskPage);
				await longTaskPage.close();
				const reopenPage = await openPage(browser, port, name);
				rows.reopen = await reopenReport(reopenPage, name);
				await reopenPage.close();
			}
			report.fixtures[name] = rows;
			process.stdout.write(`${JSON.stringify({ fixture: name, ...rows })}\n`);
		}
		await mkdir(resultsDir, { recursive: true });
		await writeFile(path.join(resultsDir, `agent-session-${report.measuredAt.replace(/[:.]/g, "-")}.json`), JSON.stringify(report, null, "\t"));
		if (args.gate) {
			const tearing = report.fixtures["claude-spinner-10s"]?.tearing;
			if (!tearing) throw new Error("gate needs the claude-spinner-10s fixture");
			if (tearing.tornStates !== 0) throw new Error(`${tearing.tornStates} model states inside a sync block became visible`);
			if (tearing.tornPaints !== 0) throw new Error(`${tearing.tornPaints} paints showed a partial frame`);
			if (tearing.multiPaintFrames !== 0) throw new Error(`${tearing.multiPaintFrames} frames painted more than once`);
			const longTask = Object.values(report.fixtures).find((rows) => rows.longTask)?.longTask;
			if (longTask && longTask.queued.longestTaskMs !== null && longTask.queued.longestTaskMs > 50) throw new Error(`queued 2 MiB feed blocked the main thread for ${longTask.queued.longestTaskMs.toFixed(1)}ms`);
			if (longTask && longTask.queued.longestFrameMs > 50) throw new Error(`queued 2 MiB feed held a frame for ${longTask.queued.longestFrameMs.toFixed(1)}ms (budget 12 ms parse + paint)`);
			const long = report.fixtures["claude-long-50k"];
			if (long?.feedSyncCost) {
				const at1k = long.feedSyncCost.find((row) => row.rows === 1000)?.medianMs;
				const at50k = long.feedSyncCost.find((row) => row.rows === 50000)?.medianMs;
				if (at1k !== null && at50k !== null && at50k > at1k * 1.2 + 0.2) throw new Error(`feed+sync at 50k rows costs ${at50k.toFixed(2)}ms vs ${at1k.toFixed(2)}ms at 1k (limit 20 % + 0.2 ms)`);
			}
			const spinner = report.fixtures["claude-spinner-10s"]?.spinner;
			if (spinner && spinner.paints > 0) {
				const rowsPerPaint = spinner.rowNodesAdded / spinner.paints;
				const nodesPerPaint = spinner.addedNodes / spinner.paints;
				process.stdout.write(`spinner: ${rowsPerPaint.toFixed(2)} row nodes and ${nodesPerPaint.toFixed(2)} DOM nodes per paint\n`);
			}
			process.stdout.write("PASS agent-session gate\n");
		}
	} catch (error) {
		process.stderr.write(`FAIL ${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	} finally {
		await browser?.close();
		await server.close();
	}
}

await main();
