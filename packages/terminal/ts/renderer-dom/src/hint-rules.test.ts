import { describe, expect, it } from "vitest";
import { DEFAULT_HINT_RULES, fileLineFields } from "./hint-rules";

function matchOf(id: string, text: string): { text: string; start: number } | null {
	const rule = DEFAULT_HINT_RULES.find((candidate) => candidate.id === id)!;
	const regex = new RegExp(rule.regex.source, rule.regex.flags);
	const match = regex.exec(text);
	if (!match) return null;
	const picked = rule.capture === "last" ? [...match].reverse().find((group, index) => group !== undefined && index < match.length - 1) ?? match[0] : match[0];
	return { text: picked, start: match.index + match[0].indexOf(picked) };
}

describe("DEFAULT_HINT_RULES", () => {
	it("carries wezterm's set minus ipfs, plus kitty's path:line, file-line first", () => {
		expect(DEFAULT_HINT_RULES.map((rule) => rule.id)).toEqual([
			"file-line", "markdown-url", "url", "diff-a", "diff-b", "docker", "path", "color", "uuid", "sha", "ip", "ipv6", "address", "number",
		]);
		expect(DEFAULT_HINT_RULES.every((rule) => rule.regex.flags.includes("g"))).toBe(true);
	});
	it("matches what each rule is for", () => {
		expect(matchOf("url", "see https://x.y/a here")?.text).toBe("https://x.y/a");
		expect(matchOf("url", "git@github.com:o/r.git")?.text).toBe("git@github.com:o/r.git");
		expect(matchOf("markdown-url", "[docs](https://x.y/md)")?.text).toBe("https://x.y/md");
		expect(matchOf("diff-a", "--- a/foo/bar.ts")?.text).toBe("foo/bar.ts");
		expect(matchOf("diff-b", "+++ b/foo/bar.ts")?.text).toBe("foo/bar.ts");
		expect(matchOf("docker", `sha256:${"c".repeat(64)}`)?.text).toBe("c".repeat(64));
		expect(matchOf("path", "edit src/app/main.ts now")?.text).toBe("src/app/main.ts");
		expect(matchOf("color", "bg #ff8800;")?.text).toBe("#ff8800");
		expect(matchOf("uuid", "id 123e4567-e89b-12d3-a456-426614174000")?.text).toBe("123e4567-e89b-12d3-a456-426614174000");
		expect(matchOf("sha", "at 0123456789abcdef done")?.text).toBe("0123456789abcdef");
		expect(matchOf("ip", "from 10.0.0.1:8080")?.text).toBe("10.0.0.1");
		expect(matchOf("address", "at 0xdeadbeef")?.text).toBe("0xdeadbeef");
		expect(matchOf("number", "took 123456 ms")?.text).toBe("123456");
		expect(matchOf("file-line", "at src/a.ts:42 line")?.text).toBe("src/a.ts:42");
		expect(DEFAULT_HINT_RULES.find((rule) => rule.id === "ipfs")).toBeUndefined();
	});
});

describe("fileLineFields", () => {
	it("splits kitty's named groups and a trailing :N, and expands a leading tilde", () => {
		const regex = new RegExp(DEFAULT_HINT_RULES[0]!.regex.source, "u");
		expect(fileLineFields(regex.exec("src/a.ts:42")!)).toEqual({ path: "src/a.ts", line: 42 });
		expect(fileLineFields(regex.exec("~/x/y.go:7")!)).toEqual({ path: "~/x/y.go", line: 7 });
	});
});
