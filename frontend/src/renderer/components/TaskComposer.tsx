import { useQuery, useQueryClient } from "@tanstack/react-query";
import { FileText, Loader2, Paperclip, X } from "lucide-react";
import {
	type ClipboardEvent,
	type DragEvent,
	type FormEvent,
	useCallback,
	useEffect,
	useId,
	useRef,
	useState,
} from "react";
import { useTranslation } from "react-i18next";
import { Button } from "./ui/button";
import { Checkbox } from "./ui/checkbox";
import { cn } from "../lib/utils";
import { paneGridBody } from "../lib/pane-grid";
import { RequiredAgentField } from "./CreateProjectAgentSheet";
import type { components } from "../../api/schema";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import { agentsQueryKey, agentsQueryOptions, refreshAgentsIfStale } from "../hooks/useAgentsQuery";
import { type FileAttachmentPayload, useFileAttachments } from "../hooks/useFileAttachments";
import { agentModelsQueryOptions } from "../hooks/useAgentModelsQuery";
import { ClaudeAccountSelect } from "./ClaudeAccountSelect";
import { TaskModelPicker } from "./TaskModelPicker";
import { preferredClaudeAccountId, useClaudeAccounts } from "../hooks/useClaudeAccounts";
import { MAX_TASK_BRIEF_LENGTH } from "../../shared/task-brief";

// Only surface the counter once it's actually useful context, not on every task.
const BRIEF_LENGTH_WARNING_THRESHOLD = MAX_TASK_BRIEF_LENGTH * 0.9;

type Project = components["schemas"]["Project"];
type DelegateAgent = components["schemas"]["DelegateTaskRequest"]["agent"];

type CreateTaskInput = {
	projectId: string;
	brief: string;
	agent?: DelegateAgent;
	model?: string;
	attachments?: FileAttachmentPayload[];
	workspaceMode?: "worktree" | "in_place";
	claudeAccountId?: string;
};

export type TaskComposerProps = {
	projectId?: string;
	onCreated: (sessionId: string) => void;
	onDirtyChange?: (dirty: boolean) => void;
	onSubmittingChange?: (submitting: boolean) => void;
	autoFocusTitle?: boolean;
};

export function TaskComposer({
	projectId,
	onCreated,
	onDirtyChange,
	onSubmittingChange,
	autoFocusTitle,
}: TaskComposerProps) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const promptId = useId();
	const modelId = useId();
	const agentId = useId();
	const worktreeId = useId();
	const fileInputRef = useRef<HTMLInputElement>(null);
	const [prompt, setPrompt] = useState("");
	const [model, setModel] = useState("");
	const [mode, setMode] = useState("");
	const [agent, setAgent] = useState("");
	const [agentTouched, setAgentTouched] = useState(false);
	const [useWorktree, setUseWorktree] = useState(false);
	const [modelTouched, setModelTouched] = useState(false);
	const [claudeAccount, setClaudeAccount] = useState("");
	const claudeAccountSelectId = useId();
	const claudeAccountsQuery = useClaudeAccounts();
	const selectedClaudeAccount = claudeAccount || preferredClaudeAccountId(claudeAccountsQuery.data);
	const [isSubmitting, setIsSubmitting] = useState(false);
	const [error, setError] = useState<string | undefined>();
	const [modelWarning, setModelWarning] = useState<string | undefined>();
	const [isDragging, setIsDragging] = useState(false);
	const {
		attachments,
		error: attachmentError,
		addFiles,
		remove: removeAttachment,
		clear: clearAttachments,
		toSettledPayload,
	} = useFileAttachments();
	const createTask = useCallback(
		async (input: CreateTaskInput): Promise<string> => {
			void captureRendererEvent("opr.renderer.task_create_requested", { project_id: input.projectId });
			try {
				const { data, error } = await apiClient.POST("/api/v1/orchestrators/delegate", {
					body: {
						projectId: input.projectId,
						brief: input.brief,
						agent: input.agent,
						model: input.model,
						workspaceMode: input.workspaceMode,
						claudeAccountId: input.claudeAccountId,
						...paneGridBody(),
						...(input.attachments && input.attachments.length > 0 ? { attachments: input.attachments } : {}),
					},
				});
				if (error) {
					throw new Error(apiErrorMessage(error, t("newTask.unableToStart")));
				}
				if (!data?.workerId) throw new Error(t("newTask.noSession"));
				void captureRendererEvent("opr.renderer.task_create_succeeded", { project_id: input.projectId });
				return data.workerId;
			} catch (err) {
				void captureRendererEvent("opr.renderer.task_create_failed", { project_id: input.projectId });
				void queryClient.invalidateQueries({ queryKey: agentsQueryKey });
				throw err instanceof Error ? err : new Error(t("newTask.unableToStart"));
			}
		},
		[queryClient, t],
	);

	const projectQuery = useQuery({
		queryKey: ["project", projectId],
		enabled: Boolean(projectId),
		queryFn: async () => {
			const { data, error: apiError } = await apiClient.GET("/api/v1/projects/{id}", {
				params: { path: { id: projectId as string } },
			});
			if (apiError) throw new Error(apiErrorMessage(apiError));
			if (data?.status !== "ok") throw new Error(t("newTask.configUnavailable"));
			return data.project as Project;
		},
	});
	const canChooseWorktree = projectQuery.data?.kind === "single_repo";
	const agentsQuery = useQuery(agentsQueryOptions);
	// Freshen the inventory on open so a just-installed or just-authenticated agent
	// is present without the user asking for it.
	useEffect(() => {
		void refreshAgentsIfStale().then((next) => {
			if (next) queryClient.setQueryData(agentsQueryKey, next);
		});
	}, [queryClient]);
	// The composer preselects the agent and model a spawn would actually use
	// instead of parking the controls on a "default" label the user has to
	// remember. Both resolved values remain directly editable.
	const projectWorkerAgent = projectQuery.data?.config?.worker?.agent ?? "";
	const globalDefaultAgent = projectQuery.data?.agent ?? "";
	const defaultWorkerAgent = projectWorkerAgent || globalDefaultAgent;
	const selectedAgent = agent || defaultWorkerAgent;
	const defaultWorkerModel =
		projectQuery.data?.config?.worker?.agentConfig?.model ?? projectQuery.data?.config?.agentConfig?.model ?? "";
	const defaultWorkerMode =
		projectQuery.data?.config?.worker?.agentConfig?.mode ?? projectQuery.data?.config?.agentConfig?.mode ?? "";
	const projectModelForSelectedAgent = selectedAgent === defaultWorkerAgent ? defaultWorkerModel : "";
	const projectModeForSelectedAgent = selectedAgent === defaultWorkerAgent ? defaultWorkerMode : "";
	const agentCatalog = agentsQuery.data;

	// Shares the picker's query key, so this is the same fetch, not a second one.
	const modelCatalogQuery = useQuery(agentModelsQueryOptions(selectedAgent, projectId ?? ""));
	const catalogDefaultOption = modelCatalogQuery.data?.models?.find((item) => item.isDefault)?.id ?? "";
	const catalogUsesModes = modelCatalogQuery.data?.selectionMode === "mode";
	const defaultModelForSelectedAgent =
		projectModelForSelectedAgent || (catalogUsesModes ? "" : catalogDefaultOption);
	const defaultModeForSelectedAgent = projectModeForSelectedAgent || (catalogUsesModes ? catalogDefaultOption : "");

	const selectedAgentLabel =
		agentCatalog?.supported?.find((item) => item.id === selectedAgent)?.label || selectedAgent;

	useEffect(() => {
		if (!agentTouched) setAgent(defaultWorkerAgent);
	}, [agentTouched, defaultWorkerAgent]);
	useEffect(() => {
		if (!modelTouched) {
			setModel(defaultModelForSelectedAgent);
			setMode(defaultModeForSelectedAgent);
		}
	}, [defaultModelForSelectedAgent, defaultModeForSelectedAgent, modelTouched]);

	const isDirty = prompt.trim() !== "" || modelTouched || attachments.length > 0;
	useEffect(() => {
		onDirtyChange?.(isDirty);
	}, [isDirty, onDirtyChange]);
	useEffect(() => () => onDirtyChange?.(false), [onDirtyChange]);

	useEffect(() => {
		onSubmittingChange?.(isSubmitting);
	}, [isSubmitting, onSubmittingChange]);
	useEffect(() => () => onSubmittingChange?.(false), [onSubmittingChange]);
	useEffect(() => () => clearAttachments(), [clearAttachments]);

	// The daemon caps the brief in bytes, not JS string length, so multi-byte
	// paste (emoji, CJK, …) needs the same encoding to stay accurate.
	const briefLength = new TextEncoder().encode(prompt).length;
	const briefTooLong = briefLength > MAX_TASK_BRIEF_LENGTH;

	const submitTask = async () => {
		if (!projectId || isSubmitting || briefTooLong) return;
		if (projectQuery.isFetching && projectQuery.data === undefined) return;

		const cleanModel = model.trim();
		const cleanMode = mode.trim();
		const requestedModel =
			modelTouched && (cleanModel !== defaultModelForSelectedAgent || cleanMode !== defaultModeForSelectedAgent)
				? cleanModel || cleanMode || undefined
				: undefined;

		setIsSubmitting(true);
		setError(undefined);
		try {
			const attachmentPayloads = await toSettledPayload();
			const sessionId = await createTask({
				projectId,
				brief: prompt,
				// The visible selection is authoritative: it is either the user's pick
				// or the resolved default, so spawning names it explicitly.
				agent: selectedAgent ? (selectedAgent as CreateTaskInput["agent"]) : undefined,
				model: requestedModel,
				attachments: attachmentPayloads.length > 0 ? attachmentPayloads : undefined,
				workspaceMode: canChooseWorktree ? (useWorktree ? "worktree" : "in_place") : undefined,
				claudeAccountId: selectedAgent === "claude-code" ? selectedClaudeAccount : undefined,
			});
			onCreated(sessionId);
		} catch (err) {
			setError(err instanceof Error ? err.message : t("newTask.unableToStart"));
		} finally {
			setIsSubmitting(false);
		}
	};

	const submit = (event: FormEvent<HTMLFormElement>) => {
		event.preventDefault();
		void submitTask();
	};

	const handlePaste = (event: ClipboardEvent<HTMLTextAreaElement>) => {
		const files = Array.from(event.clipboardData?.files ?? []);
		if (files.length === 0) return;
		event.preventDefault();
		void addFiles(files);
	};

	const handleDrop = (event: DragEvent<HTMLFormElement>) => {
		event.preventDefault();
		setIsDragging(false);
		const files = Array.from(event.dataTransfer?.files ?? []);
		if (files.length > 0) void addFiles(files);
	};

	const handleDragOver = (event: DragEvent<HTMLFormElement>) => {
		if (Array.from(event.dataTransfer?.items ?? []).some((item) => item.kind === "file")) {
			event.preventDefault();
			setIsDragging(true);
		}
	};

	return (
		<form
			onSubmit={submit}
			className="composer-prompt-surface flex flex-col transition-[background-color,box-shadow]"
			data-dragging={isDragging || undefined}
			onDrop={handleDrop}
			onDragOver={handleDragOver}
			onDragLeave={(event) => {
				const nextTarget = event.relatedTarget;
				if (!(nextTarget instanceof Node) || !event.currentTarget.contains(nextTarget)) setIsDragging(false);
			}}
		>
			{/* The whole card is one composer: the prompt carries the hierarchy and the
			    launch controls sit in its own bottom padding, without a dialog footer. */}
			<label className="sr-only" htmlFor={promptId}>
				{t("newTask.task")}
			</label>
			<textarea
				id={promptId}
				autoFocus={autoFocusTitle}
				className="min-h-(--size-composer-prompt-min) w-full resize-none bg-transparent px-4 pb-3 pt-4 text-md leading-relaxed text-foreground outline-none placeholder:text-passive"
				placeholder={t("newTask.taskPlaceholder")}
				value={prompt}
				onChange={(event) => setPrompt(event.target.value)}
				onPaste={handlePaste}
				onKeyDown={(event) => {
					if (event.key === "Enter" && !event.shiftKey && !event.altKey && !event.nativeEvent.isComposing) {
						event.preventDefault();
						event.currentTarget.form?.requestSubmit();
					}
				}}
			/>

			{attachments.length > 0 && (
				<ul className="scrollbar-none flex max-h-24 flex-wrap gap-2 overflow-y-auto px-3 pb-2">
					{attachments.map((attachment) => (
						<li
							key={attachment.id}
							className="flex min-w-0 max-w-48 items-center gap-2 rounded-md bg-surface px-1.5 py-1 text-xs text-foreground"
						>
							{attachment.dataUrl ? (
								<img src={attachment.dataUrl} alt="" className="size-7 shrink-0 rounded object-cover" />
							) : (
								<FileText
									className="size-7 shrink-0 rounded bg-input/60 p-1.5 text-muted-foreground"
									aria-hidden="true"
								/>
							)}
							<span className="min-w-0 flex-1 truncate font-medium">{attachment.name}</span>
							<button
								type="button"
								className="grid size-5 shrink-0 place-items-center rounded text-muted-foreground transition-colors hover:bg-border hover:text-foreground"
								aria-label={t("newTask.removeFile", { name: attachment.name })}
								onClick={() => removeAttachment(attachment.id)}
							>
								<X className="size-icon-sm" aria-hidden="true" />
							</button>
						</li>
					))}
				</ul>
			)}
			<input
				ref={fileInputRef}
				type="file"
				multiple
				className="hidden"
				onChange={(event) => {
					if (event.target.files) void addFiles(event.target.files);
					event.target.value = "";
				}}
			/>
			{attachmentError && (
				<p className="px-4 pb-2 text-caption text-destructive">{attachmentError}</p>
			)}

			{(error || modelWarning || briefLength > BRIEF_LENGTH_WARNING_THRESHOLD) && (
				<div className="px-3 pb-2">
					{error && (
						<div className="flex items-center justify-between gap-3 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive">
							<span>{error}</span>
						</div>
					)}
					{!error && modelWarning && <p className="text-caption text-warning">{modelWarning}</p>}
					{!error && briefLength > BRIEF_LENGTH_WARNING_THRESHOLD && (
						<p className={cn("text-caption", briefTooLong ? "text-destructive" : "text-warning")}>
							{t(briefTooLong ? "newTask.briefTooLong" : "newTask.briefNearLimit", {
								count: briefLength,
								max: MAX_TASK_BRIEF_LENGTH,
							})}
						</p>
					)}
				</div>
			)}

			<div className="composer-toolbar">
				<div className="composer-run-controls" role="group" aria-label={t("newTask.runsWith")}>
					<div className="composer-toolbar-slot">
						<RequiredAgentField
							id={agentId}
							variant="chip"
							label={t("newTask.agent")}
							placeholder={t("newTask.selectAgent")}
							value={selectedAgent}
							authorized={agentCatalog?.authorized}
							installed={agentCatalog?.installed}
							supported={agentCatalog?.supported}
							disabled={agentsQuery.isFetching && agentCatalog === undefined}
							triggerClassName="composer-toolbar-option w-full justify-between"
							onChange={(value) => {
								setAgent(value);
								setAgentTouched(true);
								// Never pair a newly selected agent with the previous agent's model.
								// The new catalog will resolve its own default into this cleared slot.
								setModel("");
								setMode("");
								setModelTouched(false);
								setClaudeAccount("default");
							}}
						/>
					</div>
					<span className="composer-toolbar-divider" aria-hidden="true" />
					<div className="composer-toolbar-slot">
						<TaskModelPicker
							id={modelId}
							agentId={selectedAgent}
							agentLabel={selectedAgentLabel}
							projectId={projectId ?? ""}
							value={model}
							mode={mode}
							onWarningChange={setModelWarning}
							onModelChange={(value) => {
								setModel(value);
								setMode("");
								setModelTouched(true);
							}}
							onModeChange={(value) => {
								setMode(value);
								setModel("");
								setModelTouched(true);
							}}
						/>
					</div>
					{selectedAgent === "claude-code" && (claudeAccountsQuery.data?.length ?? 0) > 1 ? (
						<>
							<span className="composer-toolbar-divider" aria-hidden="true" />
							<div className="composer-toolbar-slot">
								<ClaudeAccountSelect
									id={claudeAccountSelectId}
									ariaLabel={t("newTask.account")}
									value={selectedClaudeAccount}
									onChange={setClaudeAccount}
									accounts={claudeAccountsQuery.data ?? []}
									triggerClassName="composer-toolbar-option w-full justify-between"
								/>
							</div>
						</>
					) : null}
				</div>
				{canChooseWorktree && (
					<label htmlFor={worktreeId} className="flex items-center gap-1.5 text-caption text-muted-foreground">
						<Checkbox id={worktreeId} checked={useWorktree} onCheckedChange={(checked) => setUseWorktree(checked === true)} />
						{t("newTask.createWorktree")}
					</label>
				)}
				<button
					type="button"
					className="grid size-(--size-settings-action-height) place-items-center rounded-md text-muted-foreground transition-colors hover:bg-surface hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
					aria-label={t("newTask.addFile")}
					onClick={() => fileInputRef.current?.click()}
				>
					<Paperclip className="size-icon-base" aria-hidden="true" />
				</button>
				<Button
					type="submit"
					variant="primary"
					size="none"
					disabled={
					isSubmitting || !projectId || briefTooLong || (projectQuery.isFetching && projectQuery.data === undefined)
				}
					className="h-(--size-settings-action-height) min-w-(--size-composer-start-button) px-3"
				>
					{isSubmitting ? <Loader2 className="size-icon-base animate-spin" aria-hidden="true" /> : null}
					{isSubmitting ? t("newTask.starting") : t("newTask.start")}
					{!isSubmitting && (
						<kbd className="composer-keycap" aria-hidden="true">
							↵
						</kbd>
					)}
				</Button>
			</div>
		</form>
	);
}
