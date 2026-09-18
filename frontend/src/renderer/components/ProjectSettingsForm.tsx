import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import type { components } from "../../api/schema";
import { agentsQueryKey, agentsQueryOptions, refreshAgents } from "../hooks/useAgentsQuery";
import { useWorkspaceQuery, workspaceQueryKey } from "../hooks/useWorkspaceQuery";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import { spawnOrchestrator } from "../lib/spawn-orchestrator";
import { cn } from "../lib/utils";
import { newestActiveOrchestrator } from "../types/workspace";
import { RequiredAgentField } from "./CreateProjectAgentSheet";
import { buildIntake, deriveGitHubRepo, IntakeFields, type IntakeForm, intakeNeedsRule } from "./IntakeFields";
import { ReviewerSelect, reviewerTrustWarning } from "./ReviewerSelect";
import { AgentModelField } from "./settings/AgentModelField";
import { SettingsOptionMenu } from "./settings/SettingsOptionMenu";
import { SettingsInputRow, SettingsRow } from "./settings/SettingsRow";
import { SettingsSection } from "./settings/SettingsSection";
import { cleanTicketDefaults, TicketDefaultsSection } from "./settings/TicketDefaultsSection";

type Project = components["schemas"]["Project"];
type ProjectConfig = components["schemas"]["ProjectConfig"];
type TrackerIntakeConfig = components["schemas"]["TrackerIntakeConfig"];
type TicketDefaults = components["schemas"]["TicketDefaults"];

const PERMISSION_MODE_VALUES = ["default", "accept-edits", "auto", "bypass-permissions"] as const;

const projectQueryKey = (id: string) => ["project", id] as const;

export type ProjectSettingsSection = "general" | "agents" | "workflow" | "intake" | "tickets";
export interface ProjectSettingsSaveState {
	isPending: boolean;
	showSaving: boolean;
	validationError: string | null;
	mutationError: string | null;
	saved: boolean;
	replacementError: string | null;
}

export function ProjectSettingsForm({
	projectId,
	section = "general",
	onSaveState,
}: {
	projectId: string;
	section?: ProjectSettingsSection;
	onSaveState?: (state: ProjectSettingsSaveState) => void;
}) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();

	const query = useQuery({
		queryKey: projectQueryKey(projectId),
		queryFn: async () => {
			const { data, error } = await apiClient.GET("/api/v1/projects/{id}", {
				params: { path: { id: projectId } },
			});
			if (error) throw new Error(apiErrorMessage(error));
			if (data?.status !== "ok") throw new Error(t("settings.project.degraded"));
			return data.project as Project;
		},
	});

	return (
		<>
			{query.isLoading ? (
				<p className="text-sm text-settings-muted">{t("settings.project.loading")}</p>
			) : query.isError || !query.data ? (
				<p className="text-sm text-error">
					{query.error instanceof Error ? query.error.message : t("settings.project.loadFailed")}
				</p>
			) : (
				<SettingsBody
					key={projectId}
					project={query.data}
					onSaved={() => queryClient.invalidateQueries({ queryKey: workspaceQueryKey })}
					projectId={projectId}
					section={section}
					onSaveState={onSaveState}
				/>
			)}
		</>
	);
}

function SettingsBody({
	project,
	projectId,
	onSaved,
	section = "general",
	onSaveState,
}: {
	project: Project;
	projectId: string;
	onSaved: () => void;
	section?: ProjectSettingsSection;
	onSaveState?: (state: ProjectSettingsSaveState) => void;
}) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const workspaceQuery = useWorkspaceQuery();
	const config = project.config ?? {};
	const isScratchProject = project.kind === "scratch";
	const workspace = workspaceQuery.data?.find((item) => item.id === projectId);
	const activeOrchestrator = newestActiveOrchestrator(workspace?.sessions ?? []);
	const intake: TrackerIntakeConfig = config.trackerIntake ?? {};
	const [form, setForm] = useState({
		displayName: project.name,
		defaultBranch: config.defaultBranch ?? project.defaultBranch ?? "",
		sessionPrefix: config.sessionPrefix ?? "",
		workerAgent: config.worker?.agent ?? "",
		orchestratorAgent: config.orchestrator?.agent ?? "",
		workerModel: config.worker?.agentConfig?.model ?? config.agentConfig?.model ?? "",
		orchestratorModel: config.orchestrator?.agentConfig?.model ?? config.agentConfig?.model ?? "",
		workerMode: config.worker?.agentConfig?.mode ?? config.agentConfig?.mode ?? "",
		orchestratorMode: config.orchestrator?.agentConfig?.mode ?? config.agentConfig?.mode ?? "",
		permissions: config.agentConfig?.permissions ?? "",
		reviewerHarness: config.reviewers?.[0]?.harness ?? "",
		intakeEnabled: intake.enabled ?? false,
		intakeRepo: intake.repo ?? "",
		intakeAssignee: intake.assignee ?? "",
		tickets: (config.tickets ?? {}) as TicketDefaults,
	});
	const [savedAt, setSavedAt] = useState<number | null>(null);
	const [showSaving, setShowSaving] = useState(false);
	const [replacementError, setReplacementError] = useState<string | null>(null);
	const [validationError, setValidationError] = useState<string | null>(null);
	const initialOrchestratorAgent = config.orchestrator?.agent ?? "";
	const missingRequiredAgent = form.workerAgent === "" || form.orchestratorAgent === "";
	const agentsQuery = useQuery(agentsQueryOptions);
	const agentCatalog = agentsQuery.data;
	const refreshAgentsMutation = useMutation({
		mutationFn: refreshAgents,
		onSuccess: (next) => queryClient.setQueryData(agentsQueryKey, next),
	});

	const intakeForm: IntakeForm = {
		enabled: form.intakeEnabled,
		repo: form.intakeRepo,
		assignee: form.intakeAssignee,
	};
	const patchIntake = (patch: Partial<IntakeForm>) =>
		setForm((f) => ({
			...f,
			intakeEnabled: patch.enabled ?? f.intakeEnabled,
			intakeRepo: patch.repo ?? f.intakeRepo,
			intakeAssignee: patch.assignee ?? f.intakeAssignee,
		}));
	const effectiveIntakeRepo = form.intakeRepo.trim() || deriveGitHubRepo(project.repo);
	const intakeIncomplete = !isScratchProject && intakeNeedsRule(intakeForm);

	const mutation = useMutation({
		mutationFn: async () => {
			void captureRendererEvent("opr.renderer.settings_save_requested", { project_id: projectId });
			const displayName = form.displayName.trim();
			const {
				model: _legacyModel,
				mode: _legacyMode,
				...sharedAgentConfig
			} = config.agentConfig ?? {};
			const next: ProjectConfig = isScratchProject
				? {
						...scratchSupportedConfig(config),
						worker: {
							...config.worker,
							agent: form.workerAgent,
							agentConfig: buildRoleAgentConfig(config.worker?.agentConfig, form.workerModel, form.workerMode),
						},
						orchestrator: {
							...config.orchestrator,
							agent: form.orchestratorAgent,
							agentConfig: buildRoleAgentConfig(
								config.orchestrator?.agentConfig,
								form.orchestratorModel,
								form.orchestratorMode,
							),
						},
						agentConfig: blankToUndefined({
							...sharedAgentConfig,
							permissions: form.permissions || undefined,
						}),
					}
				: {
						...config,
						defaultBranch: form.defaultBranch || undefined,
						sessionPrefix: form.sessionPrefix || undefined,
						worker: {
							...config.worker,
							agent: form.workerAgent,
							agentConfig: buildRoleAgentConfig(config.worker?.agentConfig, form.workerModel, form.workerMode),
						},
						orchestrator: {
							...config.orchestrator,
							agent: form.orchestratorAgent,
							agentConfig: buildRoleAgentConfig(
								config.orchestrator?.agentConfig,
								form.orchestratorModel,
								form.orchestratorMode,
							),
						},
						agentConfig: blankToUndefined({
							...sharedAgentConfig,
							permissions: form.permissions || undefined,
						}),
						reviewers: form.reviewerHarness ? [{ harness: form.reviewerHarness }] : undefined,
						trackerIntake: buildIntake(intakeForm),
						tickets: cleanTicketDefaults(form.tickets),
					};
			const { error } = await apiClient.PUT("/api/v1/projects/{id}", {
				params: { path: { id: projectId } },
				body: { displayName, config: next },
			});
			if (error) throw new Error(apiErrorMessage(error));
			if (
				form.orchestratorAgent !== initialOrchestratorAgent ||
				(activeOrchestrator && activeOrchestrator.provider !== form.orchestratorAgent)
			) {
				try {
					await spawnOrchestrator(projectId, "settings", true);
				} catch (error) {
					return {
						replacementError:
							error instanceof Error ? error.message : t("settings.project.replaceOrchestratorFailed"),
					};
				}
			}
			return { replacementError: null };
		},
		onSuccess: (result) => {
			void captureRendererEvent("opr.renderer.settings_save_succeeded", { project_id: projectId });
			setSavedAt(Date.now());
			setReplacementError(result.replacementError);
			setValidationError(null);
			void queryClient.invalidateQueries({ queryKey: ["project", projectId] });
			onSaved();
		},
		onError: () => {
			void captureRendererEvent("opr.renderer.settings_save_failed", { project_id: projectId });
		},
	});

	useEffect(() => {
		if (!mutation.isPending) {
			setShowSaving(false);
			return;
		}
		const timeout = window.setTimeout(() => setShowSaving(true), 200);
		return () => window.clearTimeout(timeout);
	}, [mutation.isPending]);

	useEffect(() => {
		onSaveState?.({
			isPending: mutation.isPending,
			showSaving,
			validationError,
			mutationError: mutation.isError ? (mutation.error instanceof Error ? mutation.error.message : t("settings.project.saveFailed")) : null,
			saved: savedAt !== null && !mutation.isPending && !mutation.isError,
			replacementError: replacementError && !mutation.isPending && !mutation.isError ? replacementError : null,
		});
	}, [mutation.error, mutation.isError, mutation.isPending, onSaveState, replacementError, savedAt, showSaving, t, validationError]);

	useEffect(() => {
		if (savedAt === null) return;
		const timeout = window.setTimeout(() => setSavedAt(null), 1800);
		return () => window.clearTimeout(timeout);
	}, [savedAt]);

	return (
		<form
			id="project-settings-form"
			className="flex w-full flex-col gap-(--size-settings-section-gap)"
			onSubmit={(event) => {
				event.preventDefault();
				setSavedAt(null);
				setReplacementError(null);
				if (missingRequiredAgent) {
					setValidationError(t("settings.project.agentsRequired"));
					return;
				}
				if (form.displayName.trim() === "") {
					setValidationError(t("settings.project.nameRequired"));
					return;
				}
				if (intakeIncomplete) {
					setValidationError(t("settings.project.intakeAssigneeRequired"));
					return;
				}
				setValidationError(null);
				mutation.mutate();
			}}
		>
			{/* ── General: identity + workspace repos ───────────────────── */}
			{section === "general" && (
				<>
					<SettingsSection title={t("settings.project.identity")} titleHidden grouped>
						<SettingsInputRow
							label={t("settings.project.name")}
							id="projectName"
							value={form.displayName}
							onChange={(value) => setForm((f) => ({ ...f, displayName: value }))}
						/>
						<SettingsValueRow label={t("settings.project.id")} value={project.id} />
						<SettingsValueRow label={t("settings.project.kind")} value={projectKindLabel(project.kind, t)} />
						<SettingsValueRow label={t("settings.project.path")} value={project.path} href={`file://${encodeURI(project.path)}`} />
						<SettingsValueRow
							label={t("settings.project.repo")}
							value={project.repo || "—"}
							href={project.repo ? repositoryHref(project.repo) : undefined}
						/>
					</SettingsSection>
					{project.kind === "workspace" && (
						<SettingsSection title={t("settings.project.workspaceRepos")} grouped>
							{project.workspaceRepos?.length ? (
								project.workspaceRepos.map((repo) => (
									<SettingsRow key={repo.name} label={repo.name}>
										<span className="settings-row-value">
											{repo.relativePath}
											{repo.repo ? ` · ${repo.repo}` : ""}
										</span>
									</SettingsRow>
								))
							) : (
								<p className="px-1 text-xs text-settings-muted">{t("settings.project.childReposEmpty")}</p>
							)}
						</SettingsSection>
					)}
				</>
			)}

			{/* ── Agents: worker, orchestrator, model, permissions ───────── */}
			{section === "agents" && (
				<>
					<SettingsSection title={t("settings.project.agents")} titleHidden grouped>
						<RequiredAgentField
							id="workerAgent"
							variant="settings-row"
							value={form.workerAgent}
							placeholder={t("settings.project.selectWorker")}
							label={t("settings.project.defaultWorker")}
							authorized={agentCatalog?.authorized}
							installed={agentCatalog?.installed}
							supported={agentCatalog?.supported}
							disabled={agentsQuery.isFetching && agentCatalog === undefined}
							invalid={validationError !== null && form.workerAgent === ""}
							onChange={(v) =>
								setForm((f) => ({ ...f, workerAgent: v, workerModel: "", workerMode: "" }))
							}
						/>
						<AgentModelField
							role="worker"
							agentId={form.workerAgent}
							projectId={projectId}
							model={form.workerModel}
							mode={form.workerMode}
							onModelChange={(workerModel) => setForm((f) => ({ ...f, workerModel }))}
							onModeChange={(workerMode) => setForm((f) => ({ ...f, workerMode }))}
						/>
						<RequiredAgentField
							id="orchestratorAgent"
							variant="settings-row"
							value={form.orchestratorAgent}
							placeholder={t("settings.project.selectOrchestrator")}
							label={t("settings.project.defaultOrchestrator")}
							authorized={agentCatalog?.authorized}
							installed={agentCatalog?.installed}
							supported={agentCatalog?.supported}
							disabled={agentsQuery.isFetching && agentCatalog === undefined}
							invalid={validationError !== null && form.orchestratorAgent === ""}
							onChange={(v) =>
								setForm((f) => ({ ...f, orchestratorAgent: v, orchestratorModel: "", orchestratorMode: "" }))
							}
						/>
						<AgentModelField
							role="orchestrator"
							agentId={form.orchestratorAgent}
							projectId={projectId}
							model={form.orchestratorModel}
							mode={form.orchestratorMode}
							onModelChange={(orchestratorModel) => setForm((f) => ({ ...f, orchestratorModel }))}
							onModeChange={(orchestratorMode) => setForm((f) => ({ ...f, orchestratorMode }))}
						/>
						<SettingsRow label={t("settings.project.permissionMode")}>
							<PermissionModeSelect
								value={form.permissions}
								onChange={(v) => setForm((f) => ({ ...f, permissions: v }))}
							/>
						</SettingsRow>
						<SettingsRow label={t("settings.project.refreshAgents")}>
							<button
								type="button"
								aria-label={t("settings.project.refreshAgents")}
								className="settings-option-trigger inline-flex items-center gap-1.5 disabled:pointer-events-none disabled:opacity-50"
								disabled={refreshAgentsMutation.isPending}
								onClick={() => refreshAgentsMutation.mutate()}
							>
								<RefreshCw className={cn("size-icon-base", refreshAgentsMutation.isPending && "animate-spin")} aria-hidden="true" />
								{refreshAgentsMutation.isPending ? t("settings.project.refreshing") : t("settings.project.refresh")}
							</button>
						</SettingsRow>
						{refreshAgentsMutation.isError && (
							<p className="px-1 text-xs leading-row text-error">
								{refreshAgentsMutation.error instanceof Error
									? refreshAgentsMutation.error.message
									: t("settings.project.refreshFailed")}
							</p>
						)}
						{missingRequiredAgent && (
							<p className="px-1 text-xs leading-row text-error">{t("settings.project.agentsRequired")}</p>
						)}
					</SettingsSection>
				</>
			)}

			{/* ── Workflow: branch, prefix, reviewer ────────────────────── */}
			{section === "workflow" && (
				<>
					{!isScratchProject ? (
						<>
							<SettingsSection title={t("settings.project.worktrees")} grouped>
								<SettingsInputRow
									label={t("settings.project.defaultBranch")}
									id="defaultBranch"
									value={form.defaultBranch}
									placeholder="main"
									onChange={(value) => setForm((f) => ({ ...f, defaultBranch: value }))}
								/>
								<SettingsInputRow
									label={t("settings.project.sessionPrefix")}
									id="sessionPrefix"
									value={form.sessionPrefix}
									placeholder="opr"
									onChange={(value) => setForm((f) => ({ ...f, sessionPrefix: value }))}
								/>
							</SettingsSection>
							<SettingsSection title={t("settings.project.reviewers")} grouped>
								<SettingsRow label={t("settings.project.defaultReviewer")}>
									<ReviewerSelect
										value={form.reviewerHarness}
										onChange={(v) => setForm((f) => ({ ...f, reviewerHarness: v }))}
										ariaLabel={t("settings.project.defaultReviewer")}
										authorized={agentCatalog?.authorized}
										defaultOptionLabel={t("settings.project.default")}
										defaultTriggerLabel={t("settings.project.default")}
										installed={agentCatalog?.installed}
										supported={agentCatalog?.supported}
										disabled={agentsQuery.isFetching && agentCatalog === undefined}
									/>
								</SettingsRow>
								{reviewerTrustWarning(form.reviewerHarness) ? (
									<p className="px-1 text-xs leading-row text-warning" role="status">
										{reviewerTrustWarning(form.reviewerHarness)}
									</p>
								) : null}
							</SettingsSection>
						</>
					) : (
						<p className="px-1 text-xs text-settings-muted">{t("settings.project.workflow")}</p>
					)}
				</>
			)}

			{/* ── Intake: tracker intake ────────────────────────────────── */}
			{section === "intake" && (
				<>
					{!isScratchProject ? (
						<SettingsSection title={t("settings.project.trackerIntake")} grouped>
							<IntakeFields
								variant="settings"
								form={intakeForm}
								onChange={patchIntake}
								repoPreview={{ value: effectiveIntakeRepo }}
							/>
						</SettingsSection>
					) : (
						<p className="px-1 text-xs text-settings-muted">{t("settings.project.trackerIntake")}</p>
					)}
				</>
			)}

			{/* ── Tickets: planner/implementer/reviewer defaults ────────── */}
			{section === "tickets" && (
				<>
					{!isScratchProject ? (
						<SettingsSection title={t("settings.project.tickets")} grouped>
							<p className="px-1 text-xs text-settings-muted">{t("settings.project.tickets.description")}</p>
							<TicketDefaultsSection
								value={form.tickets}
								onChange={(tickets) => setForm((f) => ({ ...f, tickets }))}
								projectId={projectId}
								fallbackAgent={form.workerAgent}
								agents={agentCatalog?.supported}
							/>
						</SettingsSection>
					) : (
						<p className="px-1 text-xs text-settings-muted">{t("settings.project.tickets.scratch")}</p>
					)}
				</>
			)}
		</form>
	);
}

function SettingsValueRow({
	label,
	value,
	href,
}: {
	label: string;
	value: string;
	href?: string;
}) {
	return (
		<SettingsRow label={label}>
			{href ? (
				<a
					href={href}
					className="settings-row-value text-settings-accent hover:underline"
					title={value}
					rel={href.startsWith("http") ? "noreferrer" : undefined}
					target={href.startsWith("http") ? "_blank" : undefined}
				>
					{value}
				</a>
			) : (
				<span className="settings-row-value" title={value}>{value}</span>
			)}
		</SettingsRow>
	);
}

function PermissionModeSelect({ value, onChange }: { value: string; onChange: (value: string) => void }) {
	const { t } = useTranslation();
	const options = [
		{ value: "__default__", label: t("settings.project.default") },
		...PERMISSION_MODE_VALUES.map((value) => ({
			value,
			label:
				value === "default"
					? t("settings.project.permissionDefault")
					: value === "accept-edits"
						? t("settings.project.permissionAcceptEdits")
						: value === "auto"
							? t("settings.project.permissionAuto")
							: t("settings.project.permissionBypass"),
		})),
	];

	return (
		<SettingsOptionMenu
			aria-label={t("settings.project.permissionMode")}
			value={value || "__default__"}
			options={options}
			onChange={(v) => onChange(v === "__default__" ? "" : v)}
		/>
	);
}

function projectKindLabel(kind: string, t: TFunction): string {
	switch (kind) {
		case "single_repo":
			return t("settings.project.kind.singleRepo");
		case "workspace":
			return t("settings.project.kind.workspace");
		case "scratch":
			return t("settings.project.kind.scratch");
		default:
			return kind || t("settings.project.kind.unknown");
	}
}

function repositoryHref(repository: string): string {
	if (/^https?:\/\//i.test(repository)) return repository;
	if (repository.startsWith("git@")) {
		const [host, path] = repository.slice(4).split(":", 2);
		return `https://${host}/${path.replace(/\.git$/, "")}`;
	}
	if (repository.startsWith("ssh://")) {
		try {
			const parsed = new URL(repository);
			return `https://${parsed.hostname}${parsed.pathname.replace(/\.git$/, "")}`;
		} catch {
			return repository;
		}
	}
	return repository;
}

function scratchSupportedConfig(config: ProjectConfig): ProjectConfig {
	const { defaultBranch: _defaultBranch, reviewers: _reviewers, trackerIntake: _trackerIntake, ...supported } = config;
	return supported;
}

function blankToUndefined<T extends object>(obj: T): T | undefined {
	return Object.values(obj).some((v) => v !== undefined) ? obj : undefined;
}

function buildRoleAgentConfig(
	existing: components["schemas"]["AgentConfig"] | undefined,
	model: string,
	mode: string,
): components["schemas"]["AgentConfig"] | undefined {
	const next = { ...existing };
	if (model) next.model = model;
	else delete next.model;
	if (mode) next.mode = mode;
	else delete next.mode;
	return Object.keys(next).length > 0 ? next : undefined;
}
