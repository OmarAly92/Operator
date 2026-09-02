import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { describe, expect, it } from "vitest";

function filesMatching(pattern: string, pathspecs: string[]): string {
	try {
		return execFileSync("git", ["grep", "-l", pattern, "--", ...pathspecs], {
			encoding: "utf8",
			cwd: process.cwd(),
			stdio: "pipe",
		}).trim();
	} catch {
		return "";
	}
}

describe("xterm is gone from the renderer", () => {
	it("has no @xterm dependency", () => {
		const pkg = JSON.parse(readFileSync("package.json", "utf8"));
		const deps = { ...pkg.dependencies, ...pkg.devDependencies };
		expect(Object.keys(deps).filter((name) => name.startsWith("@xterm"))).toEqual([]);
	});

	it("has no @xterm import in renderer source", () => {
		expect(filesMatching("@xterm", ["src/renderer", ":!src/renderer/test/no-xterm.test.ts"])).toBe("");
	});

	it("has no xterm class selector left behind in renderer source", () => {
		expect(filesMatching("\\.xterm", ["src/renderer", ":!src/renderer/test/no-xterm.test.ts"])).toBe("");
	});
});
