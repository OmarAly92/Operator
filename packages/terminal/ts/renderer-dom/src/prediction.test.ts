import { describe, expect, it } from "vitest";
import { PredictionState, PREDICTION_TTL_MS } from "./prediction.js";

const key = (text: string, over: Partial<{ ctrlKey: boolean; altKey: boolean; metaKey: boolean; isComposing: boolean }> = {}) => ({
	text,
	ctrlKey: false,
	altKey: false,
	metaKey: false,
	isComposing: false,
	...over,
});

describe("PredictionState", () => {
	it("predicts a printable key at the cursor", () => {
		const state = new PredictionState();
		expect(state.register(key("a"), { row: 3, column: 5 }, 1000)).toBe(true);
		expect(state.pending()).toEqual([{ text: "a", at: { row: 3, column: 5 }, sentAtMs: 1000 }]);
	});

	it("does not predict a control or non-printable key", () => {
		const state = new PredictionState();
		expect(state.register(key("\r"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("[A"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key(""), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("c", { ctrlKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("b", { altKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("v", { metaKey: true }), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.pending()).toEqual([]);
	});

	it("does not predict a paste (more than one character in one event)", () => {
		const state = new PredictionState();
		expect(state.register(key("hello"), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("does not predict while an IME composition is open", () => {
		const state = new PredictionState();
		expect(state.register(key("a", { isComposing: true }), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("does not predict a wide or combining cluster", () => {
		const state = new PredictionState();
		expect(state.register(key("世"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("́"), { row: 0, column: 0 }, 0)).toBe(false);
		expect(state.register(key("\u{1f600}"), { row: 0, column: 0 }, 0)).toBe(false);
	});

	it("retires a prediction the real output confirms", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 6 }, "xxxxxa", 1010);
		expect(state.pending()).toEqual([]);
	});

	it("expires a prediction that is never confirmed", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		expect(state.pending()).toEqual([]);
	});

	it("suppresses prediction when the cursor did not advance after the last keystroke", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		expect(state.suppressed()).toBe(true);
		expect(state.register(key("b"), { row: 3, column: 5 }, 2000)).toBe(false);
	});

	it("leaves suppression once the cursor advances again", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		state.reconcile({ row: 3, column: 6 }, "xxxxxa", 3000);
		expect(state.suppressed()).toBe(false);
		expect(state.register(key("b"), { row: 3, column: 6 }, 3100)).toBe(true);
	});

	it("drops every prediction when the cursor jumps rows (a full redraw)", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 9, column: 0 }, "", 1010);
		expect(state.pending()).toEqual([]);
	});

	it("clear() drops everything and resets suppression", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 1);
		state.clear();
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(false);
	});

	it("confirms a typed space the row export trimmed as a trailing blank", () => {
		const state = new PredictionState();
		state.register(key(" "), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 6 }, "hello", 1010);
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(false);
	});

	it("drops a prediction the moment the cursor passes it with a different character, and suppresses", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.register(key("b"), { row: 3, column: 5 }, 1001);
		state.reconcile({ row: 3, column: 6 }, "xxxxx*", 1010);
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(true);
	});

	it("stays suppressed while the echo keeps disagreeing, and lifts once a keystroke is echoed as typed", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 6 }, "xxxxx*", 1010);
		expect(state.register(key("b"), { row: 3, column: 6 }, 1100)).toBe(false);
		state.reconcile({ row: 3, column: 7 }, "xxxxx**", 1110);
		expect(state.suppressed()).toBe(true);
		expect(state.register(key("c"), { row: 3, column: 7 }, 1200)).toBe(false);
		state.reconcile({ row: 3, column: 8 }, "xxxxx**c", 1210);
		expect(state.suppressed()).toBe(false);
	});

	it("expire() retires an aged prediction when no cursor is available to reconcile against", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.expire(1000 + PREDICTION_TTL_MS);
		expect(state.pending()).toHaveLength(1);
		state.expire(1000 + PREDICTION_TTL_MS + 1);
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(true);
	});

	it("waits as long as the caller's ttl before declaring a prediction dead", () => {
		const state = new PredictionState();
		state.register(key("a"), { row: 3, column: 5 }, 1000);
		state.reconcile({ row: 3, column: 5 }, "xxxxx", 1000 + PREDICTION_TTL_MS + 100, 1200);
		expect(state.pending()).toHaveLength(1);
		state.reconcile({ row: 3, column: 6 }, "xxxxxa", 1000 + 700, 1200);
		expect(state.pending()).toEqual([]);
		expect(state.suppressed()).toBe(false);
	});
});
