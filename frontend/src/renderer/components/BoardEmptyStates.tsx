import { Plus } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useShell } from "../lib/shell-context";
import { CreateProjectFlow } from "./CreateProjectFlow";
import { TopbarButton } from "./TopbarButton";
import { WelcomePanel } from "./WelcomePanel";

// Board empty states: first-launch welcome (`BoardWelcome`) and project board
// with no worker sessions yet (`ProjectBoardEmpty`).
export function BoardWelcome() {
	const { createProject, initializeProjectRepository } = useShell();
	return (
		<WelcomePanel>
			<div
				className="flex h-full min-h-0 items-center justify-center overflow-y-auto px-6 py-8"
				data-testid="board-welcome"
			>
				<CreateProjectFlow
					embedded
					mode="choose"
					onCreateProject={createProject}
					onInitializeProject={initializeProjectRepository}
				/>
			</div>
		</WelcomePanel>
	);
}

// Project board with a registered project but no worker sessions yet: a quiet
// invitation instead of four empty columns.
export function ProjectBoardEmpty({
	onNewTask,
	onNewTicket,
}: {
	onNewTask: () => void;
	onNewTicket?: () => void;
}) {
	const { t } = useTranslation();

	return (
		<div className="flex h-full min-h-0 items-center justify-center overflow-y-auto">
			<div className="flex w-full max-w-preview-content flex-col items-center pb-empty-offset-y text-center">
				<h2 className="text-subtitle font-semibold tracking-tight text-foreground">{t("board.empty.title")}</h2>
				<p className="mt-2 text-md-sm leading-relaxed text-muted-foreground">{t("board.empty.body")}</p>
				<div className="mt-5 flex items-center gap-2">
					<TopbarButton aria-label={t("shell.newTask")} onClick={onNewTask} variant="accent">
						<Plus className="size-icon-md" aria-hidden="true" />
						{t("shell.newTask")}
					</TopbarButton>
					{onNewTicket ? (
						<TopbarButton aria-label={t("tickets.create")} onClick={onNewTicket}>
							<Plus className="size-icon-md" aria-hidden="true" />
							{t("tickets.create")}
						</TopbarButton>
					) : null}
				</div>
			</div>
		</div>
	);
}
