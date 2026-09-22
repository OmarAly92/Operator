import { describe, expect, it } from "vitest";
import { RttMeter, RTT_WINDOW } from "./rtt.js";

describe("RttMeter", () => {
	it("has no median before any round trip completes", () => {
		const meter = new RttMeter();
		expect(meter.median()).toBe(null);
		meter.sent(100);
		expect(meter.median()).toBe(null);
	});

	it("measures one round trip", () => {
		const meter = new RttMeter();
		meter.sent(100);
		meter.received(180);
		expect(meter.median()).toBe(80);
	});

	it("takes the median of the window, not the last sample", () => {
		const meter = new RttMeter();
		for (const rtt of [100, 110, 90, 900, 105]) {
			meter.sent(0);
			meter.received(rtt);
		}
		expect(meter.median()).toBe(105);
	});

	it("keeps only the most recent RTT_WINDOW samples", () => {
		const meter = new RttMeter();
		for (let i = 0; i < RTT_WINDOW; i += 1) {
			meter.sent(0);
			meter.received(500);
		}
		for (let i = 0; i < RTT_WINDOW; i += 1) {
			meter.sent(0);
			meter.received(10);
		}
		expect(meter.median()).toBe(10);
	});

	it("ignores a receive with no matching send", () => {
		const meter = new RttMeter();
		meter.received(50);
		expect(meter.median()).toBe(null);
	});

	it("does not arm below the threshold", () => {
		const meter = new RttMeter();
		meter.sent(0);
		meter.received(7);
		expect(meter.shouldPredict(30)).toBe(false);
	});

	it("arms at or above the threshold", () => {
		const meter = new RttMeter();
		meter.sent(0);
		meter.received(107);
		expect(meter.shouldPredict(30)).toBe(true);
	});

	it("does not arm before any measurement exists", () => {
		expect(new RttMeter().shouldPredict(30)).toBe(false);
	});
});
