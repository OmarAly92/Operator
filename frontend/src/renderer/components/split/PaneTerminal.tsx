import { ArrowRight, TriangleAlert } from "lucide-react";
import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { findActiveAgentSwitch, findRecoveryRequiredAgentSwitch, useAgentSwitches } from "../../hooks/useAgentSwitches";
import { useSwitchAgentState } from "../../hooks/useSwitchAgent";
import { agentLabel } from "../../lib/agent-options";
import type { TabRef } from "../../lib/split-layout";
import { cn } from "../../lib/utils";
import { useUiStore, type Theme } from "../../stores/ui-store";
import type { ShellTerminal } from "../../hooks/useShellTerminals";
import type { TerminalTarget } from "../../types/terminal";
import type { WorkspaceSession } from "../../types/workspace";
import { AgentAvatar } from "../AgentAvatar";
import { TerminalPane } from "../TerminalPane";

export function terminalTargetForTab(tab: TabRef, shell?: ShellTerminal): TerminalTarget {
	if (tab.kind === "shell") {
		return {
			kind: "shell",
			handleId: tab.handleId,
			sessionId: tab.sessionId,
			title: shell?.title ?? "",
			generation: shell?.createdAt ?? "",
		};
	}
	if (tab.kind === "reviewer") {
		return { kind: "reviewer", handleId: tab.handleId, harness: tab.harness, sessionId: tab.sessionId };
	}
	return { kind: "worker" };
}

export function PaneTerminal({
	session,
	target,
	theme,
	daemonReady,
	focused,
}: {
	session?: WorkspaceSession;
	target: TerminalTarget;
	theme: Theme;
	daemonReady: boolean;
	focused: boolean;
}) {
	const { t } = useTranslation();
	const fontSize = useUiStore((state) => state.terminalFontSize);
	const agentSwitchesQuery = useAgentSwitches(session?.id ?? "");
	const agentSwitches = agentSwitchesQuery.data ?? [];
	const activeAgentSwitch = findActiveAgentSwitch(agentSwitches);
	const recoveryAgentSwitch = findRecoveryRequiredAgentSwitch(agentSwitches);
	const switchMutation = useSwitchAgentState(session?.id ?? "");
	const switchSource = recoveryAgentSwitch?.fromHarness ?? activeAgentSwitch?.fromHarness ?? switchMutation.input?.session.provider;
	const switchTarget = recoveryAgentSwitch?.targetHarness ?? activeAgentSwitch?.targetHarness ?? switchMutation.input?.targetHarness;
	const isSwitchingAgent = Boolean(
		!recoveryAgentSwitch && (activeAgentSwitch || switchMutation.isPending) && switchSource && switchTarget,
	);
	const switchNeedsRecovery = Boolean(recoveryAgentSwitch && switchSource && switchTarget);
	const switchPermissionRequired = Boolean(
		activeAgentSwitch?.state === "preparing_handoff" &&
			activeAgentSwitch.agentHandoffStatus === "requested" &&
			(session?.activity?.state === "blocked" || session?.activity?.state === "waiting_input"),
	);

	useEffect(() => {
		if (!switchMutation.isPending || activeAgentSwitch || recoveryAgentSwitch) return;
		void agentSwitchesQuery.refetch();
		const timer = window.setInterval(() => void agentSwitchesQuery.refetch(), 500);
		return () => window.clearInterval(timer);
	}, [activeAgentSwitch, agentSwitchesQuery.refetch, recoveryAgentSwitch, switchMutation.isPending]);

	const label =
		target.kind === "reviewer"
			? `${t("terminal.reviewer")} · ${target.harness}`
			: target.kind === "shell"
				? target.title
				: (session?.title ?? t("terminal.noSession"));
	return (
		<div aria-label={t("terminal.panelAria", { title: label })} className="relative min-h-0 flex-1" role="tabpanel">
			<div
				className="h-full min-h-0"
				data-testid="terminal-interaction-surface"
				inert={(isSwitchingAgent || switchNeedsRecovery) && !switchPermissionRequired ? true : undefined}
			>
				<TerminalPane
					daemonReady={daemonReady}
					focused={focused}
					fontSize={fontSize}
					focusRequested={switchPermissionRequired && target.kind === "worker"}
					session={session}
					terminalTarget={target}
					theme={theme}
				/>
			</div>
			{(isSwitchingAgent || switchNeedsRecovery) && switchSource && switchTarget ? (
				<AgentSwitchTerminalOverlay
					permissionRequired={switchPermissionRequired}
					recoveryRequired={switchNeedsRecovery}
					source={switchSource}
					target={switchTarget}
				/>
			) : null}
		</div>
	);
}

type AgentSwitchTerminalOverlayProps = {
	permissionRequired: boolean;
	recoveryRequired: boolean;
	source: string;
	target: string;
};

function AgentSwitchTerminalOverlay({
	permissionRequired,
	recoveryRequired,
	source,
	target,
}: AgentSwitchTerminalOverlayProps) {
	const { t } = useTranslation();
	const overlayRef = useRef<HTMLDivElement | null>(null);
	const title = recoveryRequired
		? t("switchAgent.recovery.action")
		: t("switchAgent.progressTitle", {
				source: agentLabel(source),
				target: agentLabel(target),
			});

	useEffect(() => {
		if (!permissionRequired) overlayRef.current?.focus({ preventScroll: true });
	}, [permissionRequired, recoveryRequired, source, target]);

	return (
		<div
			ref={overlayRef}
			aria-label={title}
			className={cn(
				"absolute inset-0 z-20 flex items-center justify-center",
				recoveryRequired
					? "bg-terminal/95 backdrop-blur-[3px]"
					: permissionRequired
						? "pointer-events-none bg-terminal/25"
						: "cursor-wait bg-terminal/95 backdrop-blur-[3px]",
			)}
			data-testid="agent-switch-terminal-overlay"
			tabIndex={-1}
		>
			{recoveryRequired ? (
				<div
					aria-label={title}
					className="flex max-w-md flex-col items-center gap-2 rounded-lg border border-warning/40 bg-surface/95 px-5 py-4 text-center shadow-lg"
					role="alert"
				>
					<TriangleAlert aria-hidden="true" className="size-6 text-warning" />
					<p className="font-mono text-control font-medium text-foreground">
						{t("switchAgent.recovery.title")}
					</p>
					<p className="text-caption leading-4 text-muted-foreground">
						{t("switchAgent.recovery.shortDescription")}
					</p>
				</div>
			) : (
				<div
					aria-label={title}
					aria-live="polite"
					className={cn(
						"flex flex-col items-center gap-5 px-6 text-center",
						permissionRequired && "absolute inset-x-0 top-4 gap-2",
					)}
					role="status"
				>
					<div className="flex items-center gap-5 sm:gap-7">
						<SwitchingAgentMark harness={source} />
						<div aria-hidden="true" className="flex items-center gap-2 text-accent">
							<div className="relative h-1 w-20 overflow-hidden rounded-full bg-border-strong/70 sm:w-28">
								<span className="agent-switch-transfer-pulse absolute inset-y-0 w-10 rounded-full bg-gradient-to-r from-transparent via-accent to-transparent" />
							</div>
							<ArrowRight className="size-icon-lg shrink-0" />
						</div>
						<SwitchingAgentMark harness={target} />
					</div>
					<p className="font-mono text-control font-medium text-foreground">{title}</p>
					{permissionRequired ? (
						<p className="rounded-md border border-warning/40 bg-surface/95 px-3 py-2 text-caption text-foreground shadow-lg">
							{t("switchAgent.permissionRequired")}
						</p>
					) : null}
				</div>
			)}
		</div>
	);
}

function SwitchingAgentMark({ harness }: { harness: string }) {
	return (
		<div className="flex min-w-20 flex-col items-center gap-2">
			<span className="grid size-14 place-items-center rounded-xl border border-border-strong bg-surface/90 shadow-lg shadow-black/20">
				<AgentAvatar className="size-8" decorative provider={harness} />
			</span>
			<span className="text-caption font-medium text-muted-foreground">{agentLabel(harness)}</span>
		</div>
	);
}
