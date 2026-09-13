import { describe, expect, test } from "vitest";

import { isTunnelExposed, tunnelIndicatorRefetchInterval, tunnelRefetchInterval } from "./mobile-status";

describe("mobile status helpers", () => {
	test.each([
		["downloading", true],
		["starting", true],
		["live", true],
		["reconnecting", true],
		["off", false],
		["failed", false],
		[undefined, false],
	])("isTunnelExposed(%s) = %s", (state, expected) => {
		expect(isTunnelExposed(state)).toBe(expected);
	});

	test("the dialog polls fast while in flight, slowly while live, and not at all otherwise", () => {
		expect(tunnelRefetchInterval("starting")).toBe(1000);
		expect(tunnelRefetchInterval("live")).toBe(5000);
		expect(tunnelRefetchInterval("off")).toBe(false);
	});

	test("the sidebar always polls, so a tunnel restored on boot still shows up", () => {
		expect(tunnelIndicatorRefetchInterval(undefined)).toBe(15000);
		expect(tunnelIndicatorRefetchInterval("off")).toBe(15000);
		expect(tunnelIndicatorRefetchInterval("failed")).toBe(15000);
		expect(tunnelIndicatorRefetchInterval("starting")).toBe(1000);
		expect(tunnelIndicatorRefetchInterval("live")).toBe(5000);
	});
});
