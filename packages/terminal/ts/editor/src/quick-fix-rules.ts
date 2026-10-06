import type { QuickFixRule } from "./quick-fix.js";

const GIT_COMMAND_LINE = /git/;
const GIT_PUSH_COMMAND_LINE = /git\s+push/;
const GIT_SIMILAR_OUTPUT = /(?:(most similar commands? (is|are)))/;
const GIT_TWO_DASHES_OUTPUT = /error: did you mean `--(.+)` \(with two dashes\)\?/;
const GIT_PUSH_OUTPUT = /git push --set-upstream origin (?<branchName>[^\s]+)/;
const FREE_PORT_OUTPUT = /(?:address already in use (?:0\.0\.0\.0|127\.0\.0\.1|localhost|::):|Unable to bind [^ ]*:|can't listen on port |listen EADDRINUSE [^ ]*:)(?<portNumber>\d{4,5})/;

const BRANCH_NAME = /^(?!-)[A-Za-z0-9._/@+-]+$/;
const GIT_SUBCOMMAND = /^[a-z][a-z0-9-]*$/;
const OPTION_NAME = /^[a-z][a-z0-9-]*$/;

export const gitPushSetUpstream: QuickFixRule = {
	id: "git-push-set-upstream",
	commandLine: GIT_PUSH_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_PUSH_OUTPUT, anchor: "bottom", offset: 0, length: 8 },
	fix: ({ outputMatch }) => {
		const branch = outputMatch?.groups?.branchName;
		return branch && BRANCH_NAME.test(branch) ? `git push --set-upstream origin ${branch}` : null;
	},
};

export const gitSimilar: QuickFixRule = {
	id: "git-similar",
	commandLine: GIT_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_SIMILAR_OUTPUT, anchor: "bottom", offset: 0, length: 10 },
	fix: ({ command, outputLines, lineIndex }) => {
		const suggestion = outputLines.slice(lineIndex + 1).map((line) => line.trim()).find((line) => line.length > 0);
		if (!suggestion || !GIT_SUBCOMMAND.test(suggestion)) return null;
		return command.replace(/git\s+[^\s]+/, () => `git ${suggestion}`);
	},
};

export const gitTwoDashes: QuickFixRule = {
	id: "git-two-dashes",
	commandLine: GIT_COMMAND_LINE,
	exit: "error",
	output: { line: GIT_TWO_DASHES_OUTPUT, anchor: "bottom", offset: 0, length: 2 },
	fix: ({ command, outputMatch }) => {
		const option = outputMatch?.[1];
		if (!option || !OPTION_NAME.test(option)) return null;
		const fixed = command.replace(` -${option}`, () => ` --${option}`);
		return fixed === command ? null : fixed;
	},
};

export const freePort: QuickFixRule = {
	id: "free-port",
	commandLine: /.+/,
	exit: "error",
	output: { line: FREE_PORT_OUTPUT, anchor: "bottom", offset: 0, length: 30 },
	fix: ({ outputMatch }) => {
		const port = outputMatch?.groups?.portNumber;
		return port ? `kill $(lsof -t -iTCP:${port} -sTCP:LISTEN)` : null;
	},
};

export const DEFAULT_QUICK_FIX_RULES: readonly QuickFixRule[] = Object.freeze([
	gitPushSetUpstream,
	gitSimilar,
	gitTwoDashes,
	freePort,
]);
