import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { test } from "node:test";

test("the agent-session page exposes the Plan B probes", async () => {
	const source = await readFile(new URL("./main.ts", import.meta.url), "utf8");
	for (const name of ["feedNextSynced", "rowNodesAdded", "extendSelectionByOneRow", "mountPanes", "cellMetrics", "features"]) {
		assert.ok(source.includes(`${name}(`), `${name} is missing from main.ts`);
		assert.ok(source.includes(`${name},`) || source.includes(`${name}:`), `${name} is not exported on window.__agentSession`);
	}
});
