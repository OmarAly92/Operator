import { beforeEach, describe, expect, it } from "vitest";
import { lastPaneGrid, paneGridBody, rememberPaneGrid, resetPaneGridForTests } from "./pane-grid";

describe("pane grid", () => {
	beforeEach(() => resetPaneGridForTests());

	it("is empty until a pane has been measured", () => {
		expect(lastPaneGrid()).toBeNull();
		expect(paneGridBody()).toEqual({});
	});

	it("remembers the most recent measurement", () => {
		rememberPaneGrid(80, 24);
		rememberPaneGrid(132, 43);
		expect(lastPaneGrid()).toEqual({ cols: 132, rows: 43 });
		expect(paneGridBody()).toEqual({ cols: 132, rows: 43 });
	});

	it("ignores a grid that is not a positive integer pair", () => {
		rememberPaneGrid(132, 43);
		rememberPaneGrid(0, 43);
		rememberPaneGrid(120, -1);
		rememberPaneGrid(80.5, 24);
		expect(lastPaneGrid()).toEqual({ cols: 132, rows: 43 });
	});
});
