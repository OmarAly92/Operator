import { describe, expect, it } from "vitest";
import { ElementPool } from "./element-pool";

function section(text: string): HTMLElement {
	const element = document.createElement("section");
	element.append(document.createTextNode(text));
	return element;
}

describe("ElementPool", () => {
	it("returns a pooled element once", () => {
		const pool = new ElementPool();
		const a = section("a");
		pool.put("a", a, 3);
		expect(pool.take("a")).toBe(a);
		expect(pool.take("a")).toBeUndefined();
	});
	it("evicts the least recently pooled element past capacity and empties it", () => {
		const pool = new ElementPool();
		const a = section("a");
		const b = section("b");
		pool.put("a", a, 2);
		pool.put("b", b, 2);
		pool.put("a", a, 2);
		pool.put("c", section("c"), 2);
		expect(pool.size).toBe(2);
		expect(pool.take("b")).toBeUndefined();
		expect(b.childNodes.length).toBe(0);
		expect(pool.take("a")).toBe(a);
		expect(a.childNodes.length).toBe(1);
	});
	it("clear empties every element", () => {
		const pool = new ElementPool();
		const a = section("a");
		pool.put("a", a, 2);
		pool.clear();
		expect(pool.size).toBe(0);
		expect(a.childNodes.length).toBe(0);
	});
});
