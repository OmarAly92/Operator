import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { getMock, putMock, postMock, navigateMock } = vi.hoisted(() => ({
	getMock: vi.fn(),
	putMock: vi.fn(),
	postMock: vi.fn(),
	navigateMock: vi.fn(),
}));

vi.mock("@tanstack/react-router", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@tanstack/react-router")>();
	return {
		...actual,
		useNavigate: () => navigateMock,
	};
});

vi.mock("../lib/api-client", () => ({
	apiClient: {
		GET: getMock,
		PUT: putMock,
		POST: postMock,
	},
	apiErrorCode: (error: unknown) =>
		typeof error === "object" && error !== null && "code" in error
			? String((error as { code: unknown }).code)
			: undefined,
	apiErrorRequestId: (error: unknown) =>
		typeof error === "object" && error !== null && "requestId" in error
			? String((error as { requestId: unknown }).requestId)
			: undefined,
	apiErrorMessage: (error: unknown) => {
		if (error instanceof Error) return error.message;
		if (typeof error === "object" && error !== null && "message" in error) {
			return String((error as { message: unknown }).message);
		}
		return "Request failed";
	},
}));

import { ProjectSettingsForm, type ProjectSettingsSaveState, type ProjectSettingsSection } from "./ProjectSettingsForm";
import { workspaceQueryKey } from "../hooks/useWorkspaceQuery";
import type { WorkspaceSummary } from "../types/workspace";

async function beginEdit(label: string) {
	await userEvent.click(await screen.findByRole("button", { name: `Edit ${label}` }));
	return screen.getByLabelText(label);
}

function TestProjectSettings({
	projectId,
	section,
}: {
	projectId: string;
	section?: ProjectSettingsSection;
}) {
	const [saveState, setSaveState] = useState<ProjectSettingsSaveState>({
		isPending: false,
		showSaving: false,
		validationError: null,
		mutationError: null,
		saved: false,
	});
	return (
		<>
			<ProjectSettingsForm projectId={projectId} section={section} onSaveState={setSaveState} />
			{saveState.validationError && <span>{saveState.validationError}</span>}
			{saveState.mutationError && <span>{saveState.mutationError}</span>}
			{saveState.saved && <span>{"Saved"}</span>}
		</>
	);
}

function renderSettings(projectId = "proj-1", workspaces?: WorkspaceSummary[], section?: ProjectSettingsSection) {
	const queryClient = new QueryClient({
		defaultOptions: {
			queries: { retry: false },
			mutations: { retry: false },
		},
	});
	if (workspaces) {
		queryClient.setQueryData(workspaceQueryKey, workspaces);
	}
	render(
		<QueryClientProvider client={queryClient}>
			<TestProjectSettings projectId={projectId} section={section} />
		</QueryClientProvider>,
	);
	return queryClient;
}

async function chooseOption(trigger: HTMLElement, optionName: string) {
	await userEvent.click(trigger);
	const escaped = optionName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	await userEvent.click(await screen.findByRole("menuitem", { name: new RegExp(`^${escaped}$`, "i") }));
}

function submitSettings() {
	fireEvent.submit(document.getElementById("project-settings-form")!);
}

const agentCatalogResponse = {
	data: {
		supported: [
			{ id: "claude-code", label: "Claude Code" },
			{ id: "codex", label: "Codex" },
			{ id: "copilot", label: "GitHub Copilot" },
			{ id: "cursor", label: "Cursor" },
			{ id: "goose", label: "Goose" },
			{ id: "kilocode", label: "Kilo Code" },
			{ id: "kiro", label: "Kiro" },
			{ id: "opencode", label: "OpenCode" },
			{ id: "pi", label: "Pi" },
		],
		installed: [
			{ id: "claude-code", label: "Claude Code", authStatus: "authorized" },
			{ id: "codex", label: "Codex", authStatus: "authorized" },
			{ id: "copilot", label: "GitHub Copilot", authStatus: "authorized" },
			{ id: "cursor", label: "Cursor", authStatus: "authorized" },
			{ id: "goose", label: "Goose", authStatus: "authorized" },
			{ id: "kilocode", label: "Kilo Code", authStatus: "authorized" },
			{ id: "kiro", label: "Kiro", authStatus: "unknown" },
			{ id: "opencode", label: "OpenCode", authStatus: "authorized" },
			{ id: "pi", label: "Pi", authStatus: "authorized" },
		],
		authorized: [
			{ id: "claude-code", label: "Claude Code", authStatus: "authorized" },
			{ id: "codex", label: "Codex", authStatus: "authorized" },
			{ id: "copilot", label: "GitHub Copilot", authStatus: "authorized" },
			{ id: "cursor", label: "Cursor", authStatus: "authorized" },
			{ id: "goose", label: "Goose", authStatus: "authorized" },
			{ id: "kilocode", label: "Kilo Code", authStatus: "authorized" },
			{ id: "opencode", label: "OpenCode", authStatus: "authorized" },
			{ id: "pi", label: "Pi", authStatus: "authorized" },
		],
	},
	error: undefined,
};

function mockProject(project: Record<string, unknown>) {
	getMock.mockImplementation(async (path: string) => {
		if (path === "/api/v1/agents") return agentCatalogResponse;
		if (path === "/api/v1/agents/{agent}/models") {
			return {
				data: {
					agentId: "test-agent",
					selectionMode: "text",
					models: [],
					allowCustom: true,
					source: "manual",
					fetchedAt: "2026-07-31T00:00:00Z",
					stale: false,
				},
				error: undefined,
			};
		}
		return {
			data: {
				status: "ok",
				project,
			},
			error: undefined,
		};
	});
}

beforeEach(() => {
	getMock.mockReset();
	putMock.mockReset();
	postMock.mockReset();
	navigateMock.mockReset();
	putMock.mockResolvedValue({ data: { project: {} }, error: undefined });
	postMock.mockResolvedValue({
		data: {},
		error: undefined,
		response: { status: 200 },
	});
});

describe("ProjectSettingsForm", () => {
	it("does not have its own close button (dialog handles closing)", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "",
			defaultBranch: "main",
			config: { agent: "codex" },
		});

		renderSettings();
		await screen.findByLabelText("Enable issue intake");

		expect(screen.queryByRole("button", { name: "Close settings" })).not.toBeInTheDocument();
		expect(navigateMock).not.toHaveBeenCalled();
	});

	it("does not navigate on Escape (dialog handles closing)", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "",
			defaultBranch: "main",
			config: { agent: "codex" },
		});

		renderSettings();
		await screen.findByLabelText("Enable issue intake");

		await userEvent.keyboard("{Escape}");

		expect(navigateMock).not.toHaveBeenCalled();
	});

	it("saves without touching the config it no longer edits", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "git@github.com:acme/project-one.git",
			defaultBranch: "main",
			config: {
				agent: "codex",
				agentConfig: { model: "gpt-5.4", permissions: "auto" },
				defaultBranch: "develop",
				sessionPrefix: "acme",
				reviewers: [{ harness: "claude-code" }],
			},
		});

		renderSettings("proj-1", undefined, "intake");
		await screen.findByLabelText("Enable issue intake");
		submitSettings();

		await waitFor(() => expect(putMock).toHaveBeenCalledTimes(1));
		expect(putMock).toHaveBeenCalledWith("/api/v1/projects/{id}", {
			params: { path: { id: "proj-1" } },
			body: {
				displayName: "Project One",
				config: expect.objectContaining({
					agent: "codex",
					agentConfig: { model: "gpt-5.4", permissions: "auto" },
					defaultBranch: "develop",
					sessionPrefix: "acme",
					reviewers: [{ harness: "claude-code" }],
				}),
			},
		});
	});

	it("shows the daemon validation message when the settings save fails", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "git@github.com:acme/project-one.git",
			defaultBranch: "main",
			config: { agent: "codex" },
		});
		putMock.mockResolvedValue({
			data: undefined,
			error: { message: "invalid permissions" },
		});

		renderSettings("proj-1", undefined, "intake");
		await screen.findByLabelText("Enable issue intake");
		submitSettings();

		expect(await screen.findByText("invalid permissions")).toBeInTheDocument();
		expect(screen.queryByText("Saved")).not.toBeInTheDocument();
		expect(postMock).not.toHaveBeenCalled();
	});

	it("tells scratch projects that intake is unavailable", async () => {
		mockProject({
			id: "proj-2",
			name: "Scratch",
			kind: "scratch",
			path: "/tmp/scratch",
			config: { agent: "claude-code" },
		});
		renderSettings("proj-2", undefined, "intake");
		expect(await screen.findByText("Tracker intake")).toBeInTheDocument();
		expect(screen.queryByLabelText("Enable issue intake")).not.toBeInTheDocument();
	});

	it("saves GitHub tracker intake settings, deriving the repo from the project's git origin", async () => {
		getMock.mockResolvedValue({
			data: {
				status: "ok",
				project: {
					id: "proj-1",
					name: "Project One",
					kind: "single_repo",
					path: "/repo/project-one",
					repo: "git@github.com:acme/project-one.git",
					defaultBranch: "main",
					config: {
						agent: "codex",
					},
				},
			},
			error: undefined,
		});

		renderSettings("proj-1", undefined, "intake");

		await userEvent.click(await screen.findByLabelText("Enable issue intake"));

		// Repository is display-only, derived from the project's own git origin — no input to
		// fill. Assignee is the only eligibility rule in v1.
		expect(screen.getByRole("link", { name: "acme/project-one" })).toHaveAttribute(
			"href",
			"https://github.com/acme/project-one",
		);
		await userEvent.type(await beginEdit("Assignee"), "octocat");

		submitSettings();

		await waitFor(() => expect(putMock).toHaveBeenCalledTimes(1));
		const body = putMock.mock.calls[0]?.[1]?.body;
		expect(body.config.trackerIntake).toEqual({
			enabled: true,
			provider: "github",
			assignee: "octocat",
		});
	});

	it("blocks save when intake is enabled with no assignee", async () => {
		getMock.mockResolvedValue({
			data: {
				status: "ok",
				project: {
					id: "proj-1",
					name: "Project One",
					kind: "single_repo",
					path: "/repo/project-one",
					repo: "git@github.com:acme/project-one.git",
					defaultBranch: "main",
					config: {
						agent: "codex",
					},
				},
			},
			error: undefined,
		});

		renderSettings("proj-1", undefined, "intake");

		await userEvent.click(await screen.findByLabelText("Enable issue intake"));
		submitSettings();

		expect(await screen.findAllByText("Enabling intake requires an assignee.")).toHaveLength(2);
		expect(putMock).not.toHaveBeenCalled();
	});

	it("loads and saves the ticket role defaults without touching other config", async () => {
		mockProject({
			id: "proj-1",
			name: "Project One",
			kind: "single_repo",
			path: "/repo/project-one",
			repo: "git@github.com:acme/project-one.git",
			defaultBranch: "main",
			config: {
				defaultBranch: "develop",
				agent: "claude-code",
				tickets: { planner: { agent: "claude-code", model: "claude-opus-5" } },
			},
		});

		renderSettings("proj-1", undefined, "tickets");

		expect(await screen.findByLabelText("Planner model")).toHaveValue("claude-opus-5");
		await chooseOption(screen.getByRole("button", { name: "Implementer agent" }), "Codex");
		await userEvent.type(screen.getByLabelText("Implementer model"), "gpt-5.4");
		await userEvent.click(screen.getByRole("radio", { name: "New session" }));
		await userEvent.click(screen.getByRole("switch", { name: "Skip automatic review" }));

		submitSettings();

		await waitFor(() => expect(putMock).toHaveBeenCalledTimes(1));
		expect(putMock).toHaveBeenCalledWith("/api/v1/projects/{id}", {
			params: { path: { id: "proj-1" } },
			body: {
				displayName: "Project One",
				config: expect.objectContaining({
					defaultBranch: "develop",
					tickets: {
						planner: { agent: "claude-code", model: "claude-opus-5" },
						implementer: { agent: "codex", model: "gpt-5.4" },
						reviewerMode: "new",
						disableAutoReview: true,
					},
				}),
			},
		});
	}, 20_000);

	it("tells scratch projects that tickets are unavailable", async () => {
		mockProject({
			id: "proj-2",
			name: "Scratch",
			kind: "scratch",
			path: "/tmp/scratch",
			config: { agent: "claude-code" },
		});
		renderSettings("proj-2", undefined, "tickets");
		expect(await screen.findByText("Tickets are not available for scratch projects.")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Planner agent" })).not.toBeInTheDocument();
	});
});
