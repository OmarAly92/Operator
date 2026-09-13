import { Globe } from "lucide-react";
import { useTranslation } from "react-i18next";

import { useMobileTunnelStatus } from "../hooks/useMobileTunnelStatus";
import { isTunnelExposed } from "../lib/mobile-status";
import { useUiStore } from "../stores/ui-store";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";

function useTunnelIndicator() {
	const { t } = useTranslation();
	const tunnel = useMobileTunnelStatus();
	const openConnectMobile = useUiStore((state) => state.openConnectMobile);

	let statusLine: string | null = null;
	if (tunnel && isTunnelExposed(tunnel.state)) {
		if (tunnel.state === "downloading") statusLine = t("mobile.tunnel.downloading");
		else if (tunnel.state === "starting") statusLine = t("mobile.tunnel.starting");
		else if (tunnel.state === "reconnecting") statusLine = t("mobile.tunnel.reconnecting");
		else statusLine = t("mobile.tunnel.live", { provider: tunnel.provider });
	}

	return { label: t("mobile.tunnel.enable"), statusLine, openConnectMobile };
}

export function TunnelLiveRow({ tabIndex }: { tabIndex: number }) {
	const { label, statusLine, openConnectMobile } = useTunnelIndicator();
	if (!statusLine) return null;
	return (
		<button
			aria-label={label}
			className="flex w-full items-center gap-2.5 rounded-lg border border-working/35 bg-working/12 p-2.5 text-left text-control font-medium text-working transition-colors hover:bg-working/18 [&_svg]:text-working"
			onClick={openConnectMobile}
			tabIndex={tabIndex}
			type="button"
		>
			<Globe aria-hidden="true" className="size-icon-lg shrink-0" />
			<span className="min-w-0 flex-1">
				<span className="block truncate tracking-tight">{label}</span>
				<span className="block truncate text-caption font-normal text-working">{statusLine}</span>
			</span>
			<span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 rounded-full bg-working" />
		</button>
	);
}

export function TunnelLiveRailButton({ tabIndex }: { tabIndex: number }) {
	const { label, statusLine, openConnectMobile } = useTunnelIndicator();
	if (!statusLine) return null;
	return (
		<Tooltip>
			<TooltipTrigger asChild>
				<button
					aria-label={label}
					className="grid size-9 place-items-center rounded-lg border border-working/35 bg-working/12 text-working transition-colors hover:bg-working/18 [&_svg]:size-4"
					onClick={openConnectMobile}
					tabIndex={tabIndex}
					type="button"
				>
					<Globe aria-hidden="true" />
				</button>
			</TooltipTrigger>
			<TooltipContent side="right">{statusLine}</TooltipContent>
		</Tooltip>
	);
}
