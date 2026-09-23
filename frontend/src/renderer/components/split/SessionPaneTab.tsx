import { X } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useTruncatedText } from "../../hooks/useTruncatedText";
import { getAgentActivityView } from "../../lib/session-presentation";
import { cn } from "../../lib/utils";
import type { WorkspaceSession } from "../../types/workspace";
import { AgentAvatar } from "../AgentAvatar";
import { SessionAgentTabMenu } from "../SessionAgentTabMenu";

type SessionPaneTabProps = {
	label: string;
	isActive: boolean;
	onSelect?: () => void;
	session?: WorkspaceSession;
	icon?: ReactNode;
	title?: string;
	onClose?: () => void;
};

export function SessionPaneTab({ label, isActive, onSelect, session, icon, title, onClose }: SessionPaneTabProps) {
	const { t } = useTranslation();
	const { ref, isTruncated } = useTruncatedText<HTMLButtonElement>(label);
	const activity = session ? getAgentActivityView(session.activity, t) : undefined;
	const tabIcon = session ? <AgentAvatar className="size-icon-base" decorative provider={session.provider} /> : icon;
	const tab = (
		<span
			data-terminal-role="primary"
			className={cn(
				"group relative inline-flex min-w-shell-tab-min self-stretch items-center gap-1.5 border-r border-border bg-surface px-3 text-foreground transition-colors",
				onClose && "pr-1.5",
				isActive
					? "bg-overlay text-foreground after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:bg-foreground/80"
					: "text-muted-foreground hover:bg-raised hover:text-foreground",
			)}
		>
			<button
				ref={ref}
				aria-current={isActive}
				aria-label={activity ? `${label} · ${activity.label}` : label}
				aria-selected={isActive}
				className={cn(
					"inline-flex min-w-flex-min max-w-shell-tab-max items-center gap-1.5 text-control font-medium leading-none transition-colors",
					isActive ? "text-foreground" : "text-passive group-hover:text-foreground",
				)}
				onClick={onSelect}
				role="tab"
				tabIndex={isActive ? 0 : -1}
				title={title ?? (isTruncated ? label : t("terminal.sessionAria"))}
				type="button"
			>
				{tabIcon}
				<span className="truncate">{label}</span>
				{activity ? (
					<span
						aria-hidden="true"
						className="inline-flex shrink-0 self-center items-center"
						style={{ color: activity.tone }}
						title={activity.label}
					>
						<span
							className={cn("size-1.5 rounded-full", activity.breathe && "animate-status-pulse")}
							style={{ background: activity.tone }}
						/>
					</span>
				) : null}
			</button>
			{onClose ? (
				<button
					aria-label={t("terminal.closeSessionTabNamed", { title: label })}
					className="-ml-1 inline-flex size-control-sm shrink-0 items-center justify-center rounded-sm text-passive transition-colors hover:bg-interactive-hover hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent/50"
					onClick={(event) => {
						event.stopPropagation();
						onClose();
					}}
					onContextMenu={(event) => event.stopPropagation()}
					title={t("terminal.closeSessionTab")}
					type="button"
				>
					<X aria-hidden="true" className="size-icon-sm" />
				</button>
			) : null}
		</span>
	);
	if (!session) return tab;
	return <SessionAgentTabMenu session={session}>{tab}</SessionAgentTabMenu>;
}
