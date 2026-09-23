import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");
const resultsDir = path.join(benchDir, "results");
const SCRIPT_EVENTS = new Set(["FireAnimationFrame", "FunctionCall", "TimerFire", "EvaluateScript", "EventDispatch", "RunMicrotasks", "v8.callFunction"]);
const CATEGORIES = ["devtools.timeline", "disabled-by-default-devtools.timeline", "disabled-by-default-devtools.timeline.frame", "blink"];

function parseArgs(argv) {
	const out = { css: "" };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--css") out.css = argv[++index];
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	return out;
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted.length === 0 ? null : sorted[Math.floor(sorted.length / 2)];
}

function intervalsOf(events) {
	const out = [];
	const open = new Map();
	for (const event of events) {
		if (event.ph === "X") out.push({ name: event.name, start: event.ts, end: event.ts + (event.dur ?? 0), args: event.args ?? {} });
		else if (event.ph === "B") {
			if (!open.has(event.name)) open.set(event.name, []);
			open.get(event.name).push(event);
		} else if (event.ph === "E") {
			const begin = open.get(event.name)?.pop();
			if (begin) out.push({ name: event.name, start: begin.ts, end: event.ts, args: { ...(begin.args ?? {}), ...(event.args ?? {}) } });
		}
	}
	return out;
}

function analyze(events) {
	const names = new Map();
	for (const event of events) if (event.ph === "M" && event.name === "thread_name") names.set(`${event.pid}:${event.tid}`, event.args.name);
	const byThread = new Map();
	for (const event of events) {
		if (event.ph === "M") continue;
		const key = `${event.pid}:${event.tid}`;
		if (!byThread.has(key)) byThread.set(key, []);
		byThread.get(key).push(event);
	}
	let main = null;
	let most = -1;
	for (const [key, list] of byThread) {
		if (names.get(key) !== "CrRendererMain") continue;
		const count = list.filter((event) => event.name === "Layout").length;
		if (count > most) (most = count), (main = key);
	}
	const list = (byThread.get(main) ?? []).sort((a, b) => a.ts - b.ts);
	const intervals = intervalsOf(list);
	const scripts = intervals.filter((entry) => SCRIPT_EVENTS.has(entry.name)).sort((a, b) => a.start - b.start);
	const layouts = intervals.filter((entry) => entry.name === "Layout").sort((a, b) => a.start - b.start);
	const recalcs = intervals.filter((entry) => entry.name === "UpdateLayoutTree").sort((a, b) => a.start - b.start);
	const frameStarts = list.filter((event) => event.name === "BeginMainThreadFrame").map((event) => event.ts);
	const rafs = scripts.filter((entry) => entry.name === "FireAnimationFrame").map((entry) => entry.start);
	const marks = frameStarts.length > 0 ? frameStarts : rafs;
	const inScript = (t) => scripts.some((entry) => entry.start <= t && t < entry.end);
	const frameOf = (t) => {
		let lo = 0;
		let hi = marks.length - 1;
		let found = -1;
		while (lo <= hi) {
			const mid = (lo + hi) >> 1;
			if (marks[mid] <= t) (found = mid), (lo = mid + 1);
			else hi = mid - 1;
		}
		return found;
	};
	const perFrame = new Map();
	const tally = (t, field) => {
		const frame = frameOf(t);
		if (!perFrame.has(frame)) perFrame.set(frame, { forced: 0, renderStep: 0, recalcForced: 0, recalcRenderStep: 0 });
		perFrame.get(frame)[field] += 1;
	};
	let forcedMs = 0;
	let renderStepMs = 0;
	const dirty = [];
	const total = [];
	for (const layout of layouts) {
		const forced = inScript(layout.start);
		if (forced) forcedMs += (layout.end - layout.start) / 1000;
		else renderStepMs += (layout.end - layout.start) / 1000;
		tally(layout.start, forced ? "forced" : "renderStep");
		const begin = layout.args.beginData ?? {};
		if (typeof begin.dirtyObjects === "number") dirty.push(begin.dirtyObjects);
		if (typeof begin.totalObjects === "number") total.push(begin.totalObjects);
	}
	for (const recalc of recalcs) tally(recalc.start, inScript(recalc.start) ? "recalcForced" : "recalcRenderStep");
	const frames = [...perFrame.values()];
	return {
		frameDelimiter: frameStarts.length > 0 ? "BeginMainThreadFrame" : "FireAnimationFrame",
		frameMarks: marks.length,
		layouts: layouts.length,
		forcedLayouts: layouts.filter((layout) => inScript(layout.start)).length,
		renderStepLayouts: layouts.filter((layout) => !inScript(layout.start)).length,
		forcedLayoutMs: Number(forcedMs.toFixed(1)),
		renderStepLayoutMs: Number(renderStepMs.toFixed(1)),
		framesWithLayout: frames.filter((frame) => frame.forced + frame.renderStep > 0).length,
		framesWithForcedAndRenderStep: frames.filter((frame) => frame.forced > 0 && frame.renderStep > 0).length,
		framesWithTwoOrMoreLayouts: frames.filter((frame) => frame.forced + frame.renderStep >= 2).length,
		maxLayoutsInOneFrame: Math.max(0, ...frames.map((frame) => frame.forced + frame.renderStep)),
		styleRecalcs: recalcs.length,
		forcedStyleRecalcs: recalcs.filter((recalc) => inScript(recalc.start)).length,
		renderStepStyleRecalcs: recalcs.filter((recalc) => !inScript(recalc.start)).length,
		medianDirtyObjects: median(dirty),
		medianTotalObjects: median(total),
	};
}

function selfTimeTop(profile, count) {
	const byId = new Map(profile.nodes.map((node) => [node.id, node]));
	const self = new Map();
	for (let index = 0; index < profile.samples.length; index += 1) {
		const frame = byId.get(profile.samples[index]).callFrame;
		const url = frame.url ? frame.url.replace(/^https?:\/\/[^/]+/, "").replace(/\?.*$/, "") : "";
		const key = `${frame.functionName || "(anonymous)"} ${url}${url ? `:${frame.lineNumber + 1}` : ""}`;
		self.set(key, (self.get(key) ?? 0) + (profile.timeDeltas[index] ?? 0) / 1000);
	}
	return [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, count).map(([fn, ms]) => ({ fn, selfMs: Number(ms.toFixed(1)) }));
}

async function openPane(browser, port, extra, css) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=claude-spinner-10s${css ? `&css=${encodeURIComponent(css)}` : ""}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 30000 });
	if (extra > 0) await page.evaluate((count) => window.__agentSession.mountPanes(count, "visible"), extra);
	return page;
}

async function traced(browser, port, extra, css) {
	const page = await openPane(browser, port, extra, css);
	const session = await page.context().newCDPSession(page);
	const events = [];
	session.on("Tracing.dataCollected", ({ value }) => events.push(...value));
	const complete = new Promise((resolve) => session.once("Tracing.tracingComplete", resolve));
	await session.send("Tracing.start", { transferMode: "ReportEvents", traceConfig: { includedCategories: CATEGORIES } });
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	await session.send("Tracing.end");
	await complete;
	await page.close();
	return analyze(events);
}

async function profiled(browser, port, extra, css) {
	const page = await openPane(browser, port, extra, css);
	const session = await page.context().newCDPSession(page);
	await session.send("Profiler.enable");
	await session.send("Profiler.setSamplingInterval", { interval: 100 });
	await session.send("Profiler.start");
	await page.evaluate(() => window.__agentSession.feedFrames(100, 100));
	const { profile } = await session.send("Profiler.stop");
	await page.close();
	await mkdir(resultsDir, { recursive: true });
	const file = path.join(resultsDir, `visible10-${Date.now()}.cpuprofile`);
	await writeFile(file, JSON.stringify(profile));
	return { file, top: selfTimeTop(profile, 15) };
}

const args = parseArgs(process.argv.slice(2));
const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await chromium.launch({ headless: true });
	const report = {
		measuredAt: new Date().toISOString(),
		css: args.css,
		trace: { solo: await traced(browser, port, 0, args.css), visible10: await traced(browser, port, 9, args.css) },
		profile: { visible10: await profiled(browser, port, 9, args.css) },
	};
	process.stdout.write(`${JSON.stringify(report)}\n`);
} finally {
	await browser?.close();
	await server.close();
}
