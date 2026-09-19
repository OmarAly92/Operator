import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Check, Copy } from "lucide-react";

import { cn } from "../../../lib/utils";
import { SettingsRow } from "../SettingsRow";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import type { MobileBridge } from "./useMobileBridge";
import type { Ngrok } from "./useNgrok";

interface NgrokSessionCardProps {
	bridge: MobileBridge;
	ngrok: Ngrok;
}

function statusLabelKey(status: string): "online" | "reconnecting" | "off" {
	if (status === "online") return "online";
	if (status === "reconnecting") return "reconnecting";
	return "off";
}

export function NgrokSessionCard({ bridge, ngrok }: NgrokSessionCardProps) {
	const { t } = useTranslation();
	const [copied, setCopied] = useState(false);
	const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	useEffect(() => {
		return () => {
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
		};
	}, []);

	const copyUrl = async (value: string) => {
		try {
			await navigator.clipboard.writeText(value);
			setCopied(true);
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
			copiedTimeoutRef.current = setTimeout(() => setCopied(false), 1500);
		} catch {
			return;
		}
	};

	const session = ngrok.status?.session;
	const agent = ngrok.status?.agent;
	const status = session?.status ?? "";
	const labelKey = statusLabelKey(status);
	const dotClass = labelKey === "online" ? "bg-working" : labelKey === "reconnecting" ? "bg-warning" : "bg-settings-muted";
	const ngrokIsLive = bridge.tunnel?.provider === "ngrok" && bridge.tunnel.state === "live";
	const since = ngrokIsLive ? bridge.tunnel?.since : undefined;

	return (
		<>
			<SettingsRow label={t("mobile.ngrok.session")}>
				<div className="flex min-w-0 flex-1 flex-col items-end gap-1">
					<div className="flex items-center gap-2">
						<span className={cn("size-2 shrink-0 rounded-full", dotClass)} aria-hidden="true" />
						<span className="text-sm text-settings-label">{t(`mobile.ngrok.status.${labelKey}`)}</span>
					</div>
					{session?.region && (
						<span className="text-caption text-settings-muted">
							{session.region} · {session.latency}
						</span>
					)}
					{session?.publicUrl && (
						<div className="flex min-w-0 items-center gap-2">
							<span className="tracking-settings-mono break-all text-settings-label">{session.publicUrl}</span>
							<button
								type="button"
								aria-label={copied ? t("mobile.addressCopied") : t("mobile.copyAddress")}
								className="inline-flex size-6 shrink-0 items-center justify-center text-settings-muted transition-colors hover:text-settings-label"
								onClick={() => void copyUrl(session.publicUrl)}
							>
								{copied ? <Check className="size-4" aria-hidden="true" /> : <Copy className="size-4" aria-hidden="true" />}
							</button>
						</div>
					)}
					{labelKey !== "off" && (
						<span className="text-caption text-settings-muted">
							{t("mobile.ngrok.connections", { count: session?.connections ?? 0 })},{" "}
							{t("mobile.ngrok.requests", { count: session?.httpRequests ?? 0 })}
						</span>
					)}
					{since && <span className="text-caption text-settings-muted">{t("mobile.ngrok.since", { time: new Date(since).toLocaleTimeString() })}</span>}
					<Button
						type="button"
						variant="footer"
						size="sm"
						onClick={bridge.restartTunnel}
						disabled={!bridge.tunnelOn}
					>
						{t("mobile.ngrok.restart")}
					</Button>
				</div>
			</SettingsRow>

			<SettingsRow label={t("mobile.ngrok.agent")}>
				<div className="flex min-w-0 flex-1 flex-col items-end gap-1">
					<span className="tracking-settings-mono break-all text-settings-label">{agent?.binaryPath}</span>
					<div className="flex items-center gap-2">
						<Badge variant="neutral">
							{agent?.source === "managed" ? t("mobile.ngrok.sourceManaged") : t("mobile.ngrok.sourcePath")}
						</Badge>
						<span className="text-caption text-settings-muted">{agent?.version}</span>
					</div>
					{agent?.updateAvailable && <span className="text-caption text-warning">{t("mobile.ngrok.updateAvailable")}</span>}
				</div>
			</SettingsRow>
		</>
	);
}
