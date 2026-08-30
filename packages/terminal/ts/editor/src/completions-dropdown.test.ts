import { beforeEach, describe, expect, it } from "vitest";
import { CompletionsDropdown } from "./completions-dropdown.js";

const item = (value: string, description: string | null = null) => ({
	value,
	displayValue: value,
	description,
	kind: "subcommand",
	matchedIndices: [] as number[],
});

const result = (...values: string[]) => ({
	items: values.map((value) => item(value)),
	span: { start: 4, end: 6 },
	query: "co",
});

let container: HTMLElement;
let dropdown: CompletionsDropdown;

beforeEach(() => {
	document.body.innerHTML = "";
	container = document.createElement("div");
	document.body.append(container);
	dropdown = new CompletionsDropdown();
	dropdown.mount(container);
});

const key = (name: string) =>
	new KeyboardEvent("keydown", { key: name, cancelable: true });

describe("CompletionsDropdown", () => {
	it("is closed until it is given a result", () => {
		expect(dropdown.isOpen()).toBe(false);
		expect(container.querySelector("[data-terminal-completions]")).toBeNull();
	});

	it("renders one row per item", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(container.querySelectorAll("[data-completion-row]")).toHaveLength(2);
	});

	it("selects the first row by default", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("moves the selection down and back up", () => {
		dropdown.setResult(result("commit", "checkout"));
		expect(dropdown.handleKey(key("ArrowDown"))).toBe(true);
		expect(dropdown.selected()?.value).toBe("checkout");
		expect(dropdown.handleKey(key("ArrowUp"))).toBe(true);
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("wraps the selection at both ends", () => {
		dropdown.setResult(result("commit", "checkout"));
		dropdown.handleKey(key("ArrowUp"));
		expect(dropdown.selected()?.value).toBe("checkout");
		dropdown.handleKey(key("ArrowDown"));
		expect(dropdown.selected()?.value).toBe("commit");
	});

	it("marks the selected row for the stylesheet", () => {
		dropdown.setResult(result("commit", "checkout"));
		dropdown.handleKey(key("ArrowDown"));
		const rows = container.querySelectorAll("[data-completion-row]");
		expect(rows[1]?.getAttribute("data-selected")).toBe("true");
		expect(rows[0]?.getAttribute("data-selected")).toBe("false");
	});

	it("closes on Escape and reports the key as handled", () => {
		dropdown.setResult(result("commit"));
		expect(dropdown.handleKey(key("Escape"))).toBe(true);
		expect(dropdown.isOpen()).toBe(false);
	});

	it("ignores keys while closed", () => {
		expect(dropdown.handleKey(key("ArrowDown"))).toBe(false);
	});

	it("closes when given a null result", () => {
		dropdown.setResult(result("commit"));
		dropdown.setResult(null);
		expect(dropdown.isOpen()).toBe(false);
	});

	it("closes when given an empty result", () => {
		dropdown.setResult({ items: [], span: { start: 0, end: 0 }, query: "" });
		expect(dropdown.isOpen()).toBe(false);
	});

	it("renders a description when the item carries one", () => {
		dropdown.setResult({
			items: [item("commit", "Record changes")],
			span: { start: 0, end: 0 },
			query: "",
		});
		expect(container.textContent).toContain("Record changes");
	});

	it("highlights the fuzzy-matched characters", () => {
		dropdown.setResult({
			items: [{ ...item("commit"), matchedIndices: [0, 2, 5] }],
			span: { start: 0, end: 0 },
			query: "cmt",
		});
		const marks = container.querySelectorAll("[data-completion-match]");
		expect([...marks].map((mark) => mark.textContent)).toEqual(["c", "m", "t"]);
	});

	it("removes its element on dispose", () => {
		dropdown.setResult(result("commit"));
		dropdown.dispose();
		expect(container.querySelector("[data-terminal-completions]")).toBeNull();
	});
});
