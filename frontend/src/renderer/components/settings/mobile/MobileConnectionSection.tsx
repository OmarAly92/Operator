import { useTranslation } from "react-i18next";
import type { ReactNode } from "react";
import { useEffect, useRef, useState } from "react";
import { Check, Copy, Info, Loader2 } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";

import { cn } from "../../../lib/utils";
import { pairingPayload, pairingPayloadV2 } from "../../../lib/mobile-status";
import { ConnectMobileGetApp } from "../ConnectMobileGetApp";
import { ConnectMobileSetup } from "../ConnectMobileSetup";
import { Button } from "../../ui/button";
import { Switch } from "../../ui/switch";
import type { MobileBridge } from "./useMobileBridge";

const QR_CODE_SIZE = 204;

interface MobileConnectionSectionProps {
	bridge: MobileBridge;
	children?: ReactNode;
}

export function MobileConnectionSection({ bridge, children }: MobileConnectionSectionProps) {
	const { t } = useTranslation();
	const { query, status, enabled, busy, tunnel, tunnelLive, address, actionError, toggleBridge, regenerate, setTokenOpen } = bridge;
	const [copied, setCopied] = useState<"address" | "password" | null>(null);
	const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	useEffect(() => {
		return () => {
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
		};
	}, []);

	const copyField = async (field: "address" | "password", value: string | undefined) => {
		if (!value) return;
		try {
			await navigator.clipboard.writeText(value);
			setCopied(field);
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
			copiedTimeoutRef.current = setTimeout(() => setCopied(null), 1500);
		} catch {
			return;
		}
	};

	return (
		<>
			<ConnectMobileGetApp />

			{query.isLoading ? (
				<p className="mt-6 text-center text-xs text-settings-muted">{t("mobile.checkingStatus")}</p>
			) : query.isError ? (
				<p className="mt-6 text-center text-xs text-error">
					{query.error instanceof Error ? query.error.message : t("mobile.loadFailed")}
				</p>
			) : status ? (
				<div className="mt-4 flex flex-col">
					<div className="relative flex items-start justify-between gap-3 px-3 py-3">
						<div className="flex min-w-0 flex-col gap-1 pr-2">
							<span className="text-subtitle leading-(--leading-settings-mobile-title) text-settings-label">
								{t("mobile.enable")}
							</span>
							<span className="text-caption leading-(--leading-settings-mobile-hint) text-settings-muted">
								{t("mobile.enableHint")}
							</span>
						</div>
						<div className="flex shrink-0 items-center gap-2 pt-0.5">
							{busy && <Loader2 className="size-4 animate-spin text-settings-muted" aria-hidden="true" />}
							<Switch checked={enabled} onCheckedChange={toggleBridge} disabled={busy} aria-label={t("mobile.enable")} />
						</div>
					</div>

					{children}

					{actionError && <p className="mt-3 text-xs text-error">{actionError}</p>}

					<div
						className={cn(
							"grid transition-[grid-template-rows] duration-300 ease-out",
							enabled ? "grid-rows-[1fr]" : "grid-rows-[0fr]",
						)}
						aria-hidden={!enabled}
					>
						<div className="overflow-hidden">
							<div
								className={cn(
									"mt-4 flex flex-col items-center transition-opacity duration-300 ease-out",
									enabled ? "opacity-100" : "opacity-0",
								)}
							>
								<ConnectMobileSetup port={status.port} enabled={enabled} tunnelLive={Boolean(tunnelLive)} />

								<div className="mt-6 flex w-(--size-settings-mobile-qr) flex-col items-center">
									<div className="rounded-md border border-(--color-border-settings-input) bg-white p-2">
										<QRCodeSVG
											value={
												tunnelLive && tunnel
													? pairingPayloadV2(tunnel.url, status.password)
													: pairingPayload(status.host, status.port, status.password)
											}
											size={QR_CODE_SIZE}
											className="block size-(--size-settings-mobile-qr-code)"
										/>
									</div>
									<p className="mt-4 text-sm leading-5 text-settings-muted">{t("mobile.scanToPair")}</p>
									{tunnelLive && tunnel?.provider === "cloudflared" && (
										<p className="mt-2 text-caption text-settings-muted">{t("mobile.tunnel.rescan")}</p>
									)}
									{tunnelLive && tunnel?.provider === "cloudflared" && !tunnel.hasAuthtoken && (
										<button
											type="button"
											onClick={() => setTokenOpen(true)}
											className="mt-2 text-caption text-settings-muted underline hover:text-settings-label"
										>
											{t("mobile.tunnel.tokenTitle")}
										</button>
									)}
								</div>

								{status.warning && (
									<p className="mt-6 flex w-full max-w-(--size-settings-mobile-warning) items-start gap-2 text-caption leading-(--leading-settings-mobile-warning) text-warning">
										<Info className="mt-0.5 size-3.5 shrink-0" aria-hidden="true" />
										<span>{status.warning}</span>
									</p>
								)}

								<div className="mt-6 flex w-full flex-col gap-1 px-(--size-settings-mobile-details-pad-x)">
									<div className="flex items-center gap-6 text-sm leading-5">
										<span className="w-(--size-settings-mobile-label) shrink-0 text-settings-muted">{t("mobile.address")}</span>
										<div className="flex min-w-0 items-center gap-2">
											<span className="tracking-settings-mono break-all text-settings-label">{address}</span>
											<button
												type="button"
												aria-label={copied === "address" ? t("mobile.addressCopied") : t("mobile.copyAddress")}
												tabIndex={enabled ? 0 : -1}
												className="inline-flex size-6 shrink-0 items-center justify-center text-settings-muted transition-colors hover:text-settings-label"
												onClick={() => void copyField("address", address)}
											>
												{copied === "address" ? (
													<Check className="size-4" aria-hidden="true" />
												) : (
													<Copy className="size-4" aria-hidden="true" />
												)}
											</button>
										</div>
									</div>
									<div className="flex items-center gap-6 text-sm leading-5">
										<span className="w-(--size-settings-mobile-label) shrink-0 text-settings-muted">{t("mobile.password")}</span>
										<div className="flex min-w-0 items-center gap-2">
											<span className="tracking-settings-mono text-settings-label">{status.password}</span>
											<button
												type="button"
												aria-label={copied === "password" ? t("mobile.passwordCopied") : t("mobile.copyPassword")}
												tabIndex={enabled ? 0 : -1}
												className="inline-flex size-6 shrink-0 items-center justify-center text-settings-muted transition-colors hover:text-settings-label"
												onClick={() => void copyField("password", status.password)}
											>
												{copied === "password" ? (
													<Check className="size-4" aria-hidden="true" />
												) : (
													<Copy className="size-4" aria-hidden="true" />
												)}
											</button>
										</div>
									</div>
								</div>

								<Button
									type="button"
									variant="footer"
									className="mt-5 w-(--size-settings-mobile-regen-width) rounded-md"
									onClick={regenerate}
									disabled={busy || !enabled}
									tabIndex={enabled ? 0 : -1}
								>
									{busy && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
									{t("mobile.regenerate")}
								</Button>
							</div>
						</div>
					</div>
				</div>
			) : null}
		</>
	);
}
