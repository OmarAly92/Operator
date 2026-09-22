#!/usr/bin/env node
import { performance } from "node:perf_hooks";

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
	const token = process.argv[i];
	if (!token.startsWith("--")) continue;
	const eq = token.indexOf("=");
	if (eq > 0) args.set(token.slice(2, eq), token.slice(eq + 1));
	else args.set(token.slice(2), process.argv[i + 1]?.startsWith("--") ? "true" : process.argv[++i] ?? "true");
}

const url = args.get("url") ?? "ws://127.0.0.1:3007/mux";
const sessionId = args.get("session");
const samples = Number(args.get("samples") ?? 20);
const label = args.get("label") ?? "local";
const token = args.get("token") ?? "";
const mode = args.get("mode") ?? "echo";
const quietMs = Number(args.get("quiet") ?? 1200);
const timeoutMs = Number(args.get("timeout") ?? 15000);
const claudeTimeoutMs = Number(args.get("claude-timeout") ?? 180000);
const settleMs = Number(args.get("settle") ?? 8000);
const typeDelayMs = Number(args.get("type-delay") ?? 35);
const marker = args.get("marker") ?? "BANANAS";
const expect = args.get("expect") ?? "bananas";

if (!sessionId) {
	console.error("usage: measure-remote-typing-latency.mjs --session <id> [--url ws://host/mux] [--samples 20] [--label local] [--mode echo|claude|dump] [--token <bearer>]");
	process.exit(2);
}

async function openSocket() {
	if (!token) return new WebSocket(url);
	const { createRequire } = await import("node:module");
	const require = createRequire(new URL("../frontend/package.json", import.meta.url));
	const WsCtor = require("ws");
	return new WsCtor(url, { headers: { Authorization: `Bearer ${token}` } });
}

const socket = await openSocket();
socket.binaryType = "arraybuffer";

const listeners = new Set();
let lastFrameAt = 0;
let transcript = "";

socket.addEventListener("message", (event) => {
	const raw = typeof event.data === "string" ? event.data : Buffer.from(event.data).toString("utf8");
	let msg;
	try {
		msg = JSON.parse(raw);
	} catch {
		return;
	}
	if (msg.ch !== "terminal" || msg.id !== sessionId) return;
	if (msg.type === "error") {
		console.error(`mux error: ${msg.error}`);
		process.exit(1);
	}
	if (msg.type !== "data" || typeof msg.data !== "string") return;
	const at = performance.now();
	const bytes = Buffer.from(msg.data, "base64");
	lastFrameAt = at;
	transcript += bytes.toString("utf8");
	if (transcript.length > 400_000) transcript = transcript.slice(-200_000);
	for (const listener of listeners) listener({ at, bytes });
});

function send(obj) {
	socket.send(JSON.stringify(obj));
}

function sendKeys(text) {
	send({ ch: "terminal", id: sessionId, type: "data", data: Buffer.from(text, "utf8").toString("base64") });
}

function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitQuiet(ms) {
	for (;;) {
		const since = performance.now() - lastFrameAt;
		if (since >= ms) return;
		await sleep(ms - since + 10);
	}
}

function waitFor(predicate, limitMs) {
	return new Promise((resolve) => {
		const deadline = setTimeout(() => {
			listeners.delete(listener);
			resolve(null);
		}, limitMs);
		const listener = (frame) => {
			if (!predicate(frame)) return;
			clearTimeout(deadline);
			listeners.delete(listener);
			resolve(frame.at);
		};
		listeners.add(listener);
	});
}

function quantile(values, q) {
	if (values.length === 0) return null;
	const sorted = [...values].sort((a, b) => a - b);
	const pos = (sorted.length - 1) * q;
	const lo = Math.floor(pos);
	const hi = Math.ceil(pos);
	if (lo === hi) return sorted[lo];
	return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

function stats(values) {
	return {
		n: values.length,
		min: values.length ? Math.min(...values) : null,
		median: quantile(values, 0.5),
		p95: quantile(values, 0.95),
		max: values.length ? Math.max(...values) : null,
	};
}

const PRINTABLE = "abcdefghijklmnopqrstuvwxyz";

async function measureEcho() {
	const firstByte = [];
	const visible = [];
	const rows = [];
	for (let i = 0; i < samples; i += 1) {
		await waitQuiet(quietMs);
		const ch = PRINTABLE[i % PRINTABLE.length];
		const needle = Buffer.from(ch, "utf8");
		const sentAt = performance.now();
		const firstBytePromise = waitFor(() => true, timeoutMs);
		const visiblePromise = waitFor((frame) => frame.bytes.includes(needle), timeoutMs);
		sendKeys(ch);
		const firstByteAt = await firstBytePromise;
		const visibleAt = await visiblePromise;
		const row = {
			i,
			char: ch,
			firstByteMs: firstByteAt === null ? null : firstByteAt - sentAt,
			visibleMs: visibleAt === null ? null : visibleAt - sentAt,
		};
		rows.push(row);
		if (row.firstByteMs !== null) firstByte.push(row.firstByteMs);
		if (row.visibleMs !== null) visible.push(row.visibleMs);
		await waitQuiet(quietMs);
		sendKeys(String.fromCharCode(127));
	}
	await waitQuiet(quietMs);
	return {
		label,
		url,
		mode: "echo",
		samples: rows,
		firstByteMs: stats(firstByte),
		visibleMs: stats(visible),
	};
}

async function measureClaude() {
	const firstByte = [];
	const answer = [];
	const rows = [];
	const rounds = Number(args.get("rounds") ?? 3);
	for (let i = 0; i < rounds; i += 1) {
		await waitQuiet(quietMs);
		const prompt = `Reply with the single word ${marker}${i} in lowercase and nothing else`;
		for (const ch of prompt) {
			sendKeys(ch);
			await sleep(typeDelayMs);
		}
		await waitQuiet(quietMs);
		const needle = Buffer.from(`${expect}${i}`, "utf8");
		const sentAt = performance.now();
		const firstBytePromise = waitFor(() => true, timeoutMs);
		const answerPromise = waitFor((frame) => frame.bytes.includes(needle), claudeTimeoutMs);
		sendKeys("\r");
		const firstByteAt = await firstBytePromise;
		const answerAt = await answerPromise;
		const row = {
			i,
			enterFirstByteMs: firstByteAt === null ? null : firstByteAt - sentAt,
			answerMs: answerAt === null ? null : answerAt - sentAt,
		};
		rows.push(row);
		if (row.enterFirstByteMs !== null) firstByte.push(row.enterFirstByteMs);
		if (row.answerMs !== null) answer.push(row.answerMs);
		await sleep(settleMs);
		await waitQuiet(quietMs);
	}
	return {
		label,
		url,
		mode: "claude",
		samples: rows,
		enterFirstByteMs: stats(firstByte),
		answerMs: stats(answer),
	};
}

async function dump() {
	await waitQuiet(quietMs);
	return { label, url, mode: "dump", tail: transcript.slice(-4000) };
}

socket.addEventListener("error", (event) => {
	console.error(`socket error: ${event.message ?? "unknown"}`);
	process.exit(1);
});

socket.addEventListener("open", async () => {
	send({ ch: "terminal", id: sessionId, type: "open", cols: 120, rows: 40 });
	await sleep(1500);
	let result;
	if (mode === "echo") result = await measureEcho();
	else if (mode === "claude") result = await measureClaude();
	else result = await dump();
	console.log(JSON.stringify(result, null, "\t"));
	socket.close();
	process.exit(0);
});
