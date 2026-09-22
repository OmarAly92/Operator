export type HintRule = Readonly<{ id: string; regex: RegExp; capture: "whole" | "last" }>;

export const HINT_RULE_HYPERLINK = "hyperlink";

// kitty/kittens/hints/marks.go:31-41 (FILE_EXTENSION, path_regex, default_linenum_regex)
const FILE_EXTENSION = String.raw`\.(?:[a-zA-Z0-9]{2,7}|[ahcmo])(?:\b|[^.])`;
const KITTY_PATH = String.raw`(?:\S*?/[\r\S]+)|(?:\S[\r\S]*${FILE_EXTENSION})\b`;

// wezterm/wezterm-gui/src/overlay/quickselect.rs:26-56 PATTERNS, minus ipfs
export const DEFAULT_HINT_RULES: readonly HintRule[] = [
	{ id: "file-line", regex: new RegExp(String.raw`(?<path>${KITTY_PATH}):(?<line>\d+)`, "gu"), capture: "whole" },
	{ id: "markdown-url", regex: /\[[^\]]*\]\(([^)]+)\)/gu, capture: "last" },
	{ id: "url", regex: /(?:https?:\/\/|git@|git:\/\/|ssh:\/\/|ftp:\/\/|file:\/\/)\S+/gu, capture: "whole" },
	{ id: "diff-a", regex: /--- a\/(\S+)/gu, capture: "last" },
	{ id: "diff-b", regex: /\+\+\+ b\/(\S+)/gu, capture: "last" },
	{ id: "docker", regex: /sha256:([0-9a-f]{64})/gu, capture: "last" },
	{ id: "path", regex: /(?:[.\w\-@~]+)?(?:\/+[.\w\-@]+)+/gu, capture: "whole" },
	{ id: "color", regex: /#[0-9a-fA-F]{6}/gu, capture: "whole" },
	{ id: "uuid", regex: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gu, capture: "whole" },
	{ id: "sha", regex: /[0-9a-f]{7,40}/gu, capture: "whole" },
	{ id: "ip", regex: /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/gu, capture: "whole" },
	{ id: "ipv6", regex: /[A-Fa-f0-9:]+:+[A-Fa-f0-9:]+[%\w\d]+/gu, capture: "whole" },
	{ id: "address", regex: /0x[0-9a-fA-F]+/gu, capture: "whole" },
	{ id: "number", regex: /[0-9]{4,}/gu, capture: "whole" },
];

// kitty/kittens/hints/marks.go:157-166 linenum_group_processor
export function fileLineFields(match: RegExpExecArray): { path: string; line: number } | null {
	const path = match.groups?.path;
	const line = match.groups?.line;
	if (path === undefined || line === undefined) return null;
	const trailing = /:(\d+)$/u.exec(path);
	if (trailing) return { path: path.slice(0, trailing.index), line: Number(trailing[1]) };
	return { path, line: Number(line) };
}
