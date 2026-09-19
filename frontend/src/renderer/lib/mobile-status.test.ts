import { describe, expect, test } from "vitest";

import { isTunnelExposed, pairingPayload, pairingPayloadV2, tunnelIndicatorRefetchInterval, tunnelRefetchInterval } from "./mobile-status";

describe("mobile status helpers", () => {
	test("QR payload carries host, port, and password for one-scan connect", () => {
		const s = pairingPayload("192.168.1.42", 3011, "fake-password-for-testing");
		expect(JSON.parse(s)).toEqual({ v: 1, host: "192.168.1.42", port: 3011, password: "fake-password-for-testing" });
	});

	test("v2 payload carries the url and password, and no host or port", () => {
		const payload = JSON.parse(pairingPayloadV2("https://x.ngrok-free.dev", "pw"));
		expect(payload).toEqual({ v: 2, url: "https://x.ngrok-free.dev", password: "pw" });
	});

	test("transitional states poll fast and terminal ones stop", () => {
		expect(tunnelRefetchInterval("starting")).toBe(1000);
		expect(tunnelRefetchInterval("downloading")).toBe(1000);
		expect(tunnelRefetchInterval("reconnecting")).toBe(1000);
		expect(tunnelRefetchInterval("failed")).toBe(false);
		expect(tunnelRefetchInterval("off")).toBe(false);
		expect(tunnelRefetchInterval(undefined)).toBe(false);
	});

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
