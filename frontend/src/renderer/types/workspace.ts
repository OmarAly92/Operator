import { attentionZone as presentationAttentionZone } from "../lib/session-presentation";
import type { SessionTicketRef } from "../lib/ticket-presentation";

import type { ReviewerHarnessId } from "../lib/reviewer-harnesses";

export type SessionStatus =
	| "working"
	| "pr_open"
	| "draft"
	| "ci_failed"
	| "review_pending"
	| "changes_requested"
	| "approved"
	| "mergeable"
	| "merged"
	| "needs_input"
	| "exited"
	| "no_signal"
	| "idle"
	| "terminated"
	| "unknown";

const sessionStatuses = new Set<SessionStatus>([
	"working",
	"pr_open",
	"draft",
	"ci_failed",
	"review_pending",
	"changes_requested",
	"approved",
	"mergeable",
	"merged",
	"needs_input",
	"exited",
	"no_signal",
	"idle",
	"terminated",
]);

export function toSessionStatus(status?: string, isTerminated = false): SessionStatus {
	if (status && sessionStatuses.has(status as SessionStatus)) return status as SessionStatus;
	return isTerminated ? "terminated" : "unknown";
}

export type SessionActivityState = "active" | "idle" | "waiting_input" | "blocked" | "exited" | "unknown";

const sessionActivityStates = new Set<SessionActivityState>(["active", "idle", "waiting_input", "blocked", "exited"]);

export type SessionActivity = {
	state: SessionActivityState;
	lastActivityAt: string;
};

export function toSessionActivity(
	activity?: { state?: string; lastActivityAt?: string } | null,
): SessionActivity | undefined {
	if (!activity) return undefined;
	const state = sessionActivityStates.has(activity.state as SessionActivityState)
		? (activity.state as SessionActivityState)
		: "unknown";
	return {
		state,
		lastActivityAt: activity.lastActivityAt ?? "",
	};
}

export type AgentProvider =
	| "codex"
	| "claude-code"
	| "opencode"
	| "aider"
	| "grok"
	| "droid"
	| "amp"
	| "agy"
	| "crush"
	| "cursor"
	| "qwen"
	| "copilot"
	| "goose"
	| "auggie"
	| "continue"
	| "devin"
	| "cline"
	| "kimi"
	| "muse"
	| "kiro"
	| "kilocode"
	| "vibe"
	| "pi"
	| "kimchi"
	| "autohand"
	| "fake";

/** A file changed in a worker workspace (drives the review rail). */
export type ChangedFile = {
	path: string;
	additions: number;
	deletions: number;
	staged?: boolean;
};

/** Lifecycle state of a single pull request, mirrors the daemon's enum. */
export type PRState = "open" | "draft" | "merged" | "closed";

/**
 * One attributed pull request, mirroring the daemon's SessionPRFacts wire shape.
 * A session can own many (e.g. a stack), so {@link WorkspaceSession.prs} is a
 * list. The wire carries no source/target branch or parent pointer, so the UI
 * renders a flat list of PRs, not a stack tree.
 */
export type PullRequestFacts = {
	url: string;
	number: number;
	state: PRState;
	ci: string;
	review: string;
	mergeability: string;
	reviewComments: boolean;
	updatedAt: string;
};

export type WorkspaceSession = {
	id: string;
	terminalHandleId?: string;
	workspaceId: string;
	workspaceName: string;
	title: string;
	/** Raw issue/task identifier from the daemon. Intake ids are provider-prefixed. */
	issueId?: string;
	provider: AgentProvider;
	claudeAccountId?: string;
	/** Reviewer selected for this session; absent means use the project default. */
	reviewerHarness?: ReviewerHarnessId;
	branch?: string;
	workspaceMode?: "worktree" | "in_place";
	workspacePath?: string;
	status: SessionStatus;
	/** Stack-aware PR context derived by the daemon independently of runtime activity. */
	scmStatus?: SessionStatus;
	/** One-line daemon explanation of `status`, e.g. "CI failing on PR #12". */
	statusReason?: string;
	/**
	 * What the agent reported about its own card through the Operator MCP server:
	 * waiting on the user (needs_you) or done with nothing to review in a PR.
	 */
	agentReport?: { state: "needs_you" | "ready_for_review"; reason: string };
	/** Durable runtime fact from the daemon; independent of the derived SCM-aware status. */
	isTerminated?: boolean;
	/** Daemon holds a saved task prompt it can replay into a fresh conversation. */
	hasSavedPrompt?: boolean;
	/** User preference to tear down this session when its PR set completes through a merge. */
	terminateOnPrMerge?: boolean;
	/** Whether SCM review feedback is automatically injected into the worker. */
	autoInjectReview?: boolean;
	/** ISO timestamp from the daemon — used for relative time in the inspector. */
	createdAt?: string;
	/** ISO timestamp from the daemon. */
	updatedAt: string;
	isPinned?: boolean;
	pinnedAt?: string;
	/** Raw agent lifecycle activity from the daemon. */
	activity?: SessionActivity;
	/**
	 * Live preview target set by the daemon (via `opr preview`) and streamed over
	 * CDC. When non-empty, the desktop shell opens it once in the default browser.
	 */
	previewUrl?: string;
	/**
	 * Monotonic counter the daemon bumps on every `opr preview` call (even when
	 * previewUrl is unchanged), so a repeated preview of the same target still
	 * counts as new preview work.
	 */
	previewRevision?: number;
	/**
	 * Highest previewRevision durably acknowledged as opened externally. A
	 * revision ahead of this value is pending and opens once; an acknowledged one
	 * never re-opens after a restart or rerender.
	 */
	previewOpenedRevision?: number;
	/** The session's git diff against its base, when known. */
	changedFiles?: ChangedFile[];
	/** Pre-filled commit subject for the Git rail, when known. */
	commitMessage?: string;
	/**
	 * The session's attributed pull requests. One session can own many (a stack
	 * or independent PRs); empty when none are open yet. Status aggregation is
	 * done server-side, so {@link status} already reflects all of these.
	 */
	prs: PullRequestFacts[];
	ticket?: SessionTicketRef;
};

// Tracker providers whose ids the intake daemon stamps sessions with, in
// "<provider>:<native>" form. Adding a provider (Linear, Jira, ...) later is
// just another prefix in this list — no caller of canonicalTrackerIssueId
// needs to change.
const TRACKER_PROVIDER_PREFIXES = ["github:"] as const;

/**
 * The provider-prefixed issue id if `issueId` came from tracker intake, or
 * undefined for manually created sessions (whose issueId, if any, is a plain
 * task title with no provider prefix).
 */
export function canonicalTrackerIssueId(issueId?: string): string | undefined {
	if (!issueId) return undefined;
	return TRACKER_PROVIDER_PREFIXES.some((prefix) => issueId.startsWith(prefix)) ? issueId : undefined;
}

export type ProjectKind = "single_repo" | "workspace" | "scratch";

const projectKinds = new Set<ProjectKind>(["single_repo", "workspace", "scratch"]);

export function toProjectKind(kind?: string): ProjectKind | undefined {
	return projectKinds.has(kind as ProjectKind) ? (kind as ProjectKind) : undefined;
}

export type WorkspaceRepoSummary = {
	name: string;
	relativePath: string;
	repo: string;
};

// Open PRs (actionable) sort above merged/closed; ties break by number.
const prStateRank: Record<PRState, number> = { open: 0, draft: 1, merged: 2, closed: 3 };

/** A session's PRs ordered actionable-first (open, draft, merged, closed). */
export function sortedPRs(session: WorkspaceSession): PullRequestFacts[] {
	return [...session.prs].sort((a, b) => prStateRank[a.state] - prStateRank[b.state] || a.number - b.number);
}

/** PRs still in flight (open or draft). */
export function openPRs(session: WorkspaceSession): PullRequestFacts[] {
	return session.prs.filter((pr) => pr.state === "open" || pr.state === "draft");
}

export function mergedPRCount(session: WorkspaceSession): number {
	return session.prs.filter((pr) => pr.state === "merged").length;
}

/** The highest-priority PR for compact one-line surfaces (board card, sidebar). */
export function primaryPR(session: WorkspaceSession): PullRequestFacts | undefined {
	return sortedPRs(session)[0];
}

export function sessionIsActive(session: WorkspaceSession): boolean {
	return session.isTerminated !== true && session.status !== "terminated";
}

export function sessionNeedsAttention(session: WorkspaceSession): boolean {
	return presentationAttentionZone(session) === "action";
}

export { attentionZone, attentionZoneLabel, attentionZoneOrder } from "../lib/session-presentation";
export type { AttentionZone } from "../lib/session-presentation";
export type { SessionTicketRef } from "../lib/ticket-presentation";

export type WorkspaceSummary = {
	id: string;
	name: string;
	kind?: ProjectKind;
	path: string;
	workspaceRepos?: WorkspaceRepoSummary[];
	type?: "main" | "worktree";
	accentColor?: string;
	diff?: {
		additions: number;
		deletions: number;
	};
	sessions: WorkspaceSession[];
};

export function toAgentProvider(provider?: string): AgentProvider {
	switch (provider) {
		case "claude-code":
		case "opencode":
		case "aider":
		case "grok":
		case "droid":
		case "amp":
		case "agy":
		case "crush":
		case "cursor":
		case "qwen":
		case "copilot":
		case "goose":
		case "auggie":
		case "continue":
		case "devin":
		case "cline":
		case "kimi":
		case "muse":
		case "kiro":
		case "kilocode":
		case "vibe":
		case "pi":
		case "kimchi":
		case "autohand":
		case "fake":
			return provider;
		default:
			return "codex";
	}
}
