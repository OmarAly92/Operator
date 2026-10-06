import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { canSwitchAgentHarness, SwitchAgentDialog } from "../components/SwitchAgentDialog";
import { agentLabel } from "../lib/agent-options";
import { sessionIsActive, type WorkspaceSession } from "../types/workspace";
import { findActiveAgentSwitch, findRecoveryRequiredAgentSwitch, useAgentSwitches } from "./useAgentSwitches";
import { clearSwitchAgentState, useSwitchAgentState } from "./useSwitchAgent";

export function useSwitchAgentAction(session: WorkspaceSession) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const [open, setOpen] = useState(false);
	const switches = useAgentSwitches(session.id).data ?? [];
	const activeSwitch = findActiveAgentSwitch(switches);
	const recoverySwitch = findRecoveryRequiredAgentSwitch(switches);
	const switchMutation = useSwitchAgentState(session.id);
	const targetHarness = activeSwitch?.targetHarness ?? switchMutation.input?.targetHarness;
	const switching = Boolean(!recoverySwitch && (activeSwitch || (switchMutation.isPending && targetHarness)));
	const recovery = Boolean(recoverySwitch);

	useEffect(() => {
		if (switchMutation.error) setOpen(true);
	}, [switchMutation.error]);

	const available =
		!session.isTerminated &&
		canSwitchAgentHarness(session.provider) &&
		(recovery || switching || sessionIsActive(session));

	const label = recovery
		? t("switchAgent.recovery.action")
		: switching && targetHarness
			? t("switchAgent.inProgress", { target: agentLabel(targetHarness) })
			: t("switchAgent.action");

	const handleOpenChange = (nextOpen: boolean) => {
		setOpen(nextOpen);
		if (!nextOpen && switchMutation.error) {
			clearSwitchAgentState(queryClient, session.id);
		}
	};

	const dialog =
		available && open ? <SwitchAgentDialog onOpenChange={handleOpenChange} open session={session} /> : null;

	return { available, label, recovery, switching, open: () => setOpen(true), dialog };
}
