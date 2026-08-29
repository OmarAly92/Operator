import { describe, expect, it } from "vitest";
import { selectionToBlockRange } from "./selection";

function fixture(): HTMLElement {
	const root = document.createElement("div");
	root.innerHTML = "";
	for (const id of ["0:1", "0:2"]) {
		const block = document.createElement("section");
		block.dataset.terminalBlockId = id;
		for (let r = 0; r < 2; r += 1) {
			const row = document.createElement("div");
			row.dataset.terminalRow = String(r);
			row.textContent = `block ${id} row ${r}`;
			block.append(row);
		}
		root.append(block);
	}
	document.body.append(root);
	return root;
}

describe("selectionToBlockRange", () => {
	it("returns null when nothing is selected", () => {
		const root = fixture();
		expect(selectionToBlockRange(root, window.getSelection()!)).toBeNull();
	});

	it("maps a selection inside one block to that block", () => {
		const root = fixture();
		const row = root.querySelector("[data-terminal-row]")!;
		const range = document.createRange();
		range.selectNodeContents(row);
		const selection = window.getSelection()!;
		selection.removeAllRanges();
		selection.addRange(range);

		const result = selectionToBlockRange(root, selection);
		expect(result?.startBlock).toBe("0:1");
		expect(result?.endBlock).toBe("0:1");
	});

	it("maps a selection spanning two blocks to both ends", () => {
		const root = fixture();
		const rows = root.querySelectorAll("[data-terminal-row]");
		const range = document.createRange();
		range.setStart(rows[0], 0);
		range.setEnd(rows[3], 0);
		const selection = window.getSelection()!;
		selection.removeAllRanges();
		selection.addRange(range);

		const result = selectionToBlockRange(root, selection);
		expect(result?.startBlock).toBe("0:1");
		expect(result?.endBlock).toBe("0:2");
	});
});
