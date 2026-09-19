import { useTranslation } from "react-i18next";
import { Loader2 } from "lucide-react";

import { cn } from "../../../lib/utils";
import { NgrokAuthtokenDialog } from "../NgrokAuthtokenDialog";
import { TunnelConfirmDialog } from "../TunnelConfirmDialog";
import { Switch } from "../../ui/switch";
import type { MobileBridge } from "./useMobileBridge";

interface MobilePublicAccessSectionProps {
	bridge: MobileBridge;
	onManageNgrok?: () => void;
}

export function MobilePublicAccessSection({ bridge, onManageNgrok }: MobilePublicAccessSectionProps) {
	const { t } = useTranslation();
	const { tunnel, tunnelOn, tunnelBusy, enabled, toggleTunnel, confirmOpen, setConfirmOpen, confirmTunnel, tokenOpen, setTokenOpen, invalidate } =
		bridge;

	const message = (() => {
		if (!tunnel) return null;
		switch (tunnel.state) {
			case "downloading":
				return t("mobile.tunnel.downloading");
			case "starting":
				return t("mobile.tunnel.starting");
			case "reconnecting":
				return t("mobile.tunnel.reconnecting");
			case "live":
				return tunnel.lastProvider && tunnel.lastProvider !== tunnel.provider
					? t("mobile.tunnel.liveFallback", { provider: tunnel.provider, skipped: tunnel.lastProvider, reason: tunnel.fallbackReason })
					: t("mobile.tunnel.live", { provider: tunnel.provider });
			case "failed":
				return tunnel.error || t("mobile.tunnel.failed");
			default:
				return null;
		}
	})();

	return (
		<>
			{tunnel && (
				<div className="relative flex items-start justify-between gap-3 px-3 py-3">
					<div className="flex min-w-0 flex-col gap-1 pr-2">
						<span className="text-subtitle leading-(--leading-settings-mobile-title) text-settings-label">
							{t("mobile.tunnel.enable")}
						</span>
						<span className="text-caption leading-(--leading-settings-mobile-hint) text-settings-muted">
							{t("mobile.tunnel.enableHint")}
						</span>
						{message && (
							<span
								className={cn(
									"text-caption leading-(--leading-settings-mobile-hint)",
									tunnel.state === "failed" ? "text-error" : "text-settings-muted",
								)}
							>
								{message}
							</span>
						)}
						{onManageNgrok && (
							<button type="button" onClick={onManageNgrok} className="w-fit text-caption text-settings-muted underline hover:text-settings-label">
								{t("mobile.ngrok.manage")}
							</button>
						)}
					</div>
					<div className="flex shrink-0 items-center gap-2 pt-0.5">
						{tunnelBusy && <Loader2 className="size-4 animate-spin text-settings-muted" aria-hidden="true" />}
						<Switch
							checked={tunnelOn}
							onCheckedChange={toggleTunnel}
							disabled={!enabled || tunnelBusy}
							aria-label={t("mobile.tunnel.enable")}
						/>
					</div>
				</div>
			)}

			<TunnelConfirmDialog open={confirmOpen} onOpenChange={setConfirmOpen} onConfirm={confirmTunnel} />
			<NgrokAuthtokenDialog open={tokenOpen} onOpenChange={setTokenOpen} onSaved={invalidate} />
		</>
	);
}
