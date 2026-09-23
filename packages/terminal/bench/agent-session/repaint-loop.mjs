import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, webkit } from "playwright";
import { createServer } from "vite";

const benchDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const configFile = path.join(benchDir, "vite.config.ts");

function parseArgs(argv) {
	const out = { browser: "chromium", css: "", frames: 100 };
	for (let index = 0; index < argv.length; index += 1) {
		if (argv[index] === "--browser") out.browser = argv[++index];
		else if (argv[index] === "--css") out.css = argv[++index];
		else if (argv[index] === "--frames") out.frames = Number(argv[++index]);
		else throw new Error(`unsupported argument ${argv[index]}`);
	}
	if (out.browser !== "chromium" && out.browser !== "webkit") throw new Error(`unsupported browser ${out.browser}`);
	return out;
}

async function loop(browser, port, extra, args) {
	const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
	await page.goto(`http://127.0.0.1:${port}/agent-session/index.html?fixture=claude-spinner-10s${args.css ? `&css=${encodeURIComponent(args.css)}` : ""}`);
	await page.waitForFunction(() => window.__agentSessionReady === true, undefined, { timeout: 60000 });
	if (extra > 0) await page.evaluate((count) => window.__agentSession.mountPanes(count, "visible"), extra);
	const result = await page.evaluate((frames) => window.__agentSession.repaintLoop(frames), args.frames);
	await page.close();
	return result;
}

const args = parseArgs(process.argv.slice(2));
const server = await createServer({ configFile, logLevel: "error" });
let browser;
try {
	await server.listen(0);
	const port = server.httpServer.address().port;
	browser = await (args.browser === "webkit" ? webkit : chromium).launch({ headless: true });
	const report = {
		measuredAt: new Date().toISOString(),
		browser: args.browser,
		css: args.css,
		solo: await loop(browser, port, 0, args),
		visible10: await loop(browser, port, 9, args),
	};
	process.stdout.write(`${JSON.stringify(report)}\n`);
} catch (error) {
	process.stderr.write(`FAIL ${error instanceof Error ? error.stack : String(error)}\n`);
	process.exitCode = 1;
} finally {
	await browser?.close();
	await server.close();
}
