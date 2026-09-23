import { describe, expect, it } from "vitest";
import { shellBlockNotification } from "./shell-block-notifications";

const base = { sourceId: "osc133-1-0", exitCode: 0, startedAt: "2026-09-23T10:00:00.000Z", finishedAt: "2026-09-23T10:00:15.000Z" };

describe("shellBlockNotification", () => {
	it("notifies a command that ran at least the notify threshold", () => {
		expect(shellBlockNotification(base, "h1")).toEqual({ id: "block-finished:h1:osc133-1-0", exitCode: 0, durationMs: 15_000 });
	});

	it("stays quiet under the threshold", () => {
		expect(shellBlockNotification({ ...base, finishedAt: "2026-09-23T10:00:05.000Z" }, "h1")).toBeNull();
	});

	it("stays quiet when a time does not parse", () => {
		expect(shellBlockNotification({ ...base, startedAt: "" }, "h1")).toBeNull();
	});
});
