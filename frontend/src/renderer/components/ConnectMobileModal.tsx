import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { useEffect, useRef, useState } from "react";
import { Check, Copy, Info, Loader2, X } from "lucide-react";
import { QRCodeSVG } from "qrcode.react";
import { apiClient, apiErrorMessage } from "../lib/api-client";
import { captureRendererEvent } from "../lib/telemetry";
import { cn } from "../lib/utils";
import { ConnectMobileGetApp } from "./settings/ConnectMobileGetApp";
import { ConnectMobileSetup } from "./settings/ConnectMobileSetup";
import { NgrokAuthtokenDialog } from "./settings/NgrokAuthtokenDialog";
import { TunnelConfirmDialog } from "./settings/TunnelConfirmDialog";
import {
	fetchMobileStatus,
	mobileStatusQueryKey,
	pairingPayload,
	pairingPayloadV2,
	tunnelRefetchInterval,
} from "../lib/mobile-status";
import { tunnelAlreadyConfirmed } from "../lib/tunnel-confirm";
import {
	Dialog,
	DialogClose,
	DialogContent,
	DialogDescription,
	DialogHeader,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogHeaderClass,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Switch } from "./ui/switch";

/** Matches `--size-settings-mobile-qr-code`; qrcode.react needs a px number. */
const QR_CODE_SIZE = 204;

interface ConnectMobileModalProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
}

// ConnectMobileModal lets a user pair the mobile app with this desktop over
// the LAN bridge. A single "Allow mobile pairing" toggle sits at the top; flipping it
// on starts the bridge and reveals the pairing details below the toggle row —
// a QR code (host/port/password), the plaintext address + password with a copy
// affordance, and a Regenerate action. Flipping it off tears the bridge down.
export function ConnectMobileModal({ open, onOpenChange }: ConnectMobileModalProps) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const [copied, setCopied] = useState<"address" | "password" | null>(null);
	const [confirmOpen, setConfirmOpen] = useState(false);
	const [tokenOpen, setTokenOpen] = useState(false);
	const copiedTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	useEffect(() => {
		return () => {
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
		};
	}, []);

	const query = useQuery({
		queryKey: mobileStatusQueryKey,
		queryFn: fetchMobileStatus,
		enabled: open,
		refetchInterval: (q) => tunnelRefetchInterval(q.state.data?.tunnel?.state),
	});

	// Reported once per open, and only after the status query resolves, so
	// bridge_enabled reflects the real state rather than the `false` default that
	// every open would otherwise report. Reset on close so reopening counts again.
	const reportedOpen = useRef(false);
	const initialEnabled = query.data?.enabled;
	useEffect(() => {
		if (!open) {
			reportedOpen.current = false;
			return;
		}
		if (initialEnabled === undefined || reportedOpen.current) return;
		reportedOpen.current = true;
		void captureRendererEvent("opr.renderer.mobile_connect_opened", { bridge_enabled: initialEnabled });
	}, [open, initialEnabled]);

	const invalidate = () => {
		void queryClient.invalidateQueries({ queryKey: mobileStatusQueryKey });
	};

	const enable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/enable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const disable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/disable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const regenerate = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/regenerate");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const tunnelEnable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/enable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const tunnelDisable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/disable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const status = query.data;
	const enabled = status?.enabled ?? false;
	const busy = enable.isPending || disable.isPending || regenerate.isPending;

	const clearActionErrors = () => {
		enable.reset();
		disable.reset();
		regenerate.reset();
		tunnelEnable.reset();
		tunnelDisable.reset();
	};

	const tunnel = status?.tunnel;
	const tunnelLive = tunnel?.state === "live" && tunnel.url !== "";
	const address = tunnelLive && tunnel ? tunnel.url : status ? `${status.host}:${status.port}` : undefined;
	const tunnelBusy = tunnelEnable.isPending || tunnelDisable.isPending;
	const tunnelOn = tunnelLive || tunnel?.state === "starting" || tunnel?.state === "downloading" || tunnel?.state === "reconnecting";
	const needsAuthtoken = tunnel?.needsAuthtoken ?? false;
	const [seenNeedsAuthtoken, setSeenNeedsAuthtoken] = useState(false);
	if (needsAuthtoken !== seenNeedsAuthtoken) {
		setSeenNeedsAuthtoken(needsAuthtoken);
		if (needsAuthtoken) setTokenOpen(true);
	}

	const tunnelMessage = (() => {
		if (!tunnel) return null;
		switch (tunnel.state) {
			case "downloading":
				return t("mobile.tunnel.downloading");
			case "starting":
				return t("mobile.tunnel.starting");
			case "reconnecting":
				return t("mobile.tunnel.reconnecting");
			case "live":
				return t("mobile.tunnel.live", { provider: tunnel.provider });
			case "failed":
				return tunnel.error || t("mobile.tunnel.failed");
			default:
				return null;
		}
	})();

	const onTunnelToggle = (next: boolean) => {
		if (tunnelBusy) return;
		clearActionErrors();
		if (!next) {
			tunnelDisable.mutate();
			return;
		}
		if (!tunnelAlreadyConfirmed()) {
			setConfirmOpen(true);
			return;
		}
		tunnelEnable.mutate();
	};

	const copyField = async (field: "address" | "password", value: string | undefined) => {
		if (!value) return;
		try {
			await navigator.clipboard.writeText(value);
			setCopied(field);
			if (copiedTimeoutRef.current) clearTimeout(copiedTimeoutRef.current);
			copiedTimeoutRef.current = setTimeout(() => setCopied(null), 1500);
		} catch {
			// Clipboard can reject (permissions / non-secure context).
		}
	};

	const onToggle = (next: boolean) => {
		if (busy) return;
		clearActionErrors();
		// Enabling is the step that starts the bridge and reveals the QR, so this
		// paired with opr.mobile.device_connected (emitted by the daemon when a
		// phone actually authenticates) is what shows how many people who set this
		// up ever finish the scan.
		const report = (outcome: "succeeded" | "failed") => {
			void captureRendererEvent("opr.renderer.mobile_bridge_toggled", { enabled: next, outcome });
		};
		const mutation = next ? enable : disable;
		mutation.mutate(undefined, { onSuccess: () => report("succeeded"), onError: () => report("failed") });
	};

	const actionError =
		(enable.error instanceof Error && enable.error.message) ||
		(disable.error instanceof Error && disable.error.message) ||
		(regenerate.error instanceof Error && regenerate.error.message) ||
		(tunnelEnable.error instanceof Error && tunnelEnable.error.message) ||
		(tunnelDisable.error instanceof Error && tunnelDisable.error.message) ||
		null;

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent
				showCloseButton={false}
				className={cn(settingsDialogContentClass, "w-[min(var(--size-settings-mobile-dialog),calc(100vw-var(--space-8)))]")}
			>
				<DialogClose asChild>
					<button
						type="button"
						className="settings-dialog-close-button settings-close-button"
						aria-label={t("mobile.close")}
					>
						<X className="size-5" aria-hidden="true" />
					</button>
				</DialogClose>
				{/* The get-app QR and setup steps can push this past a short window,
				    so the body scrolls rather than clipping under the screen edges. */}
				<DialogHeader className={cn(settingsDialogHeaderClass, "items-start text-left")}>
					<DialogTitle className="settings-dialog-title text-left">{t("mobile.title")}</DialogTitle>
					<DialogDescription className="max-w-(--size-settings-mobile-desc) text-left text-control font-normal leading-4 text-settings-muted">
						{t("mobile.description")}
					</DialogDescription>
				</DialogHeader>
				<div className={cn(settingsDialogBodyClass, "max-h-[80vh] gap-0 pt-6 scrollbar-none")}>
					<ConnectMobileGetApp />

					{query.isLoading ? (
						<p className="mt-6 text-center text-xs text-settings-muted">{t("mobile.checkingStatus")}</p>
					) : query.isError ? (
						<p className="mt-6 text-center text-xs text-error">
							{query.error instanceof Error ? query.error.message : t("mobile.loadFailed")}
						</p>
					) : status ? (
						<div className="mt-4 flex flex-col">
							{/* Toggle row — always visible. Flipping it starts/stops the bridge. */}
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
									<Switch
										checked={enabled}
										onCheckedChange={onToggle}
										disabled={busy}
										aria-label={t("mobile.enable")}
									/>
								</div>
							</div>

							{tunnel && (
								<div className="relative flex items-start justify-between gap-3 px-3 py-3">
									<div className="flex min-w-0 flex-col gap-1 pr-2">
										<span className="text-subtitle leading-(--leading-settings-mobile-title) text-settings-label">
											{t("mobile.tunnel.enable")}
										</span>
										<span className="text-caption leading-(--leading-settings-mobile-hint) text-settings-muted">
											{t("mobile.tunnel.enableHint")}
										</span>
										{tunnelMessage && (
											<span
												className={cn(
													"text-caption leading-(--leading-settings-mobile-hint)",
													tunnel.state === "failed" ? "text-error" : "text-settings-muted",
												)}
											>
												{tunnelMessage}
											</span>
										)}
									</div>
									<div className="flex shrink-0 items-center gap-2 pt-0.5">
										{tunnelBusy && <Loader2 className="size-4 animate-spin text-settings-muted" aria-hidden="true" />}
										<Switch
											checked={Boolean(tunnelOn)}
											onCheckedChange={onTunnelToggle}
											disabled={!enabled || tunnelBusy}
											aria-label={t("mobile.tunnel.enable")}
										/>
									</div>
								</div>
							)}

							{actionError && <p className="mt-3 text-xs text-error">{actionError}</p>}

							{/* Pairing details — expand/collapse with the enable toggle. */}
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
										{/* Steps sit above the QR so the LAN/Tailscale choice is on screen
										    the moment the bridge turns on, with no scrolling. */}
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
											onClick={() => {
												clearActionErrors();
												regenerate.mutate();
											}}
											disabled={busy || !enabled}
											tabIndex={enabled ? 0 : -1}
										>
											{regenerate.isPending && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
											{t("mobile.regenerate")}
										</Button>
									</div>
								</div>
							</div>
						</div>
					) : null}
				</div>
				<TunnelConfirmDialog
					open={confirmOpen}
					onOpenChange={setConfirmOpen}
					onConfirm={() => tunnelEnable.mutate()}
				/>
				<NgrokAuthtokenDialog open={tokenOpen} onOpenChange={setTokenOpen} onSaved={invalidate} />
			</DialogContent>
		</Dialog>
	);
}
