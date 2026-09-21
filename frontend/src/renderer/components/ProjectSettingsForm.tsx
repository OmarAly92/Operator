import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { useEffect, useState } from "react";
import type { components } from "../../api/schema";
import { agentsQueryOptions } from "../hooks/useAgentsQuery";
import { workspaceQueryKey } from "../hooks/useWorkspaceQuery";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import { buildIntake, deriveGitHubRepo, IntakeFields, type IntakeForm, intakeNeedsRule } from "./IntakeFields";
import { SettingsSection } from "./settings/SettingsSection";
import { cleanTicketDefaults, TicketDefaultsSection } from "./settings/TicketDefaultsSection";

type Project = components["schemas"]["Project"];
type ProjectConfig = components["schemas"]["ProjectConfig"];
type TrackerIntakeConfig = components["schemas"]["TrackerIntakeConfig"];
type TicketDefaults = components["schemas"]["TicketDefaults"];

const projectQueryKey = (id: string) => ["project", id] as const;

export type ProjectSettingsSection = "intake" | "tickets";
export interface ProjectSettingsSaveState {
	isPending: boolean;
	showSaving: boolean;
	validationError: string | null;
	mutationError: string | null;
	saved: boolean;
}

export function ProjectSettingsForm({
	projectId,
	section = "intake",
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
	section = "intake",
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
	const config = project.config ?? {};
	const isScratchProject = project.kind === "scratch";
	const intake: TrackerIntakeConfig = config.trackerIntake ?? {};
	const [form, setForm] = useState({
		intakeEnabled: intake.enabled ?? false,
		intakeRepo: intake.repo ?? "",
		intakeAssignee: intake.assignee ?? "",
		tickets: (config.tickets ?? {}) as TicketDefaults,
	});
	const [savedAt, setSavedAt] = useState<number | null>(null);
	const [showSaving, setShowSaving] = useState(false);
	const [validationError, setValidationError] = useState<string | null>(null);
	const agentCatalog = useQuery(agentsQueryOptions).data;

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
			const next: ProjectConfig = isScratchProject
				? config
				: {
						...config,
						trackerIntake: buildIntake(intakeForm),
						tickets: cleanTicketDefaults(form.tickets),
					};
			const { error } = await apiClient.PUT("/api/v1/projects/{id}", {
				params: { path: { id: projectId } },
				body: { displayName: project.name, config: next },
			});
			if (error) throw new Error(apiErrorMessage(error));
		},
		onSuccess: () => {
			void captureRendererEvent("opr.renderer.settings_save_succeeded", { project_id: projectId });
			setSavedAt(Date.now());
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
		});
	}, [mutation.error, mutation.isError, mutation.isPending, onSaveState, savedAt, showSaving, t, validationError]);

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
				if (intakeIncomplete) {
					setValidationError(t("settings.project.intakeAssigneeRequired"));
					return;
				}
				setValidationError(null);
				mutation.mutate();
			}}
		>
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

			{section === "tickets" && (
				<>
					{!isScratchProject ? (
						<SettingsSection title={t("settings.project.tickets")} grouped>
							<p className="px-1 text-xs text-settings-muted">{t("settings.project.tickets.description")}</p>
							<TicketDefaultsSection
								value={form.tickets}
								onChange={(tickets) => setForm((f) => ({ ...f, tickets }))}
								projectId={projectId}
								fallbackAgent={config.agent ?? ""}
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
