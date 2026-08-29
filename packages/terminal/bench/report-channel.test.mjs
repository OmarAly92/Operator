import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import { installReportChannel } from "./report-channel.mjs";

class PageDouble extends EventEmitter {
	async exposeFunction(name, callback) {
		assert.equal(name, "__operatorBenchmarkReport");
		this.callback = callback;
	}

	async report(value) {
		await this.callback(value);
	}
}

test("bounds the wait for a browser benchmark report", async () => {
	const page = new PageDouble();
	const channel = await installReportChannel(page, 10);
	await assert.rejects(channel.result, /timed out after 10 ms/);
	assert.equal(page.listenerCount("crash"), 0);
	assert.equal(page.listenerCount("pageerror"), 0);
});

test("rejects page crashes and page errors", async () => {
	for (const [event, value, message] of [
		["crash", undefined, /benchmark page crashed/],
		["pageerror", new Error("render failed"), /benchmark page error: render failed/],
	]) {
		const page = new PageDouble();
		const channel = await installReportChannel(page, 1000);
		const rejected = assert.rejects(channel.result, message);
		page.emit(event, value);
		await rejected;
		assert.equal(page.listenerCount("crash"), 0);
		assert.equal(page.listenerCount("pageerror"), 0);
	}
});

test("resolves reports and rejects browser-reported failures", async () => {
	const successPage = new PageDouble();
	const success = await installReportChannel(successPage, 1000);
	await successPage.report({ renderer: "xterm" });
	assert.deepEqual(await success.result, { renderer: "xterm" });

	const failurePage = new PageDouble();
	const failure = await installReportChannel(failurePage, 1000);
	const rejected = assert.rejects(failure.result, /paint failed/);
	await failurePage.report({ error: "paint failed" });
	await rejected;
});

test("disposes a pending report channel", async () => {
	const page = new PageDouble();
	const channel = await installReportChannel(page, 1000);
	channel.dispose();
	assert.equal(page.listenerCount("crash"), 0);
	assert.equal(page.listenerCount("pageerror"), 0);
});
