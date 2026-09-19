import { useState } from "react";
import { useTranslation } from "react-i18next";

import { operatorBridge } from "../../../lib/bridge";
import { SettingsRow } from "../SettingsRow";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../../ui/dialog";
import { Button } from "../../ui/button";
import type { MobileBridge } from "./useMobileBridge";
import type { Ngrok } from "./useNgrok";

const NGROK_DASHBOARD_URL = "https://dashboard.ngrok.com";

interface NgrokCredentialCardProps {
	bridge: MobileBridge;
	ngrok: Ngrok;
}

export function NgrokCredentialCard({ bridge, ngrok }: NgrokCredentialCardProps) {
	const { t } = useTranslation();
	const [confirmOpen, setConfirmOpen] = useState(false);
	const credential = ngrok.status?.credential;
	const present = credential?.present ?? false;
	const source = credential?.source ?? "";

	const value = !present
		? t("mobile.ngrok.notLoggedIn")
		: source === "system"
			? t("mobile.ngrok.systemLogin", { path: credential?.systemConfigPath ?? "" })
			: t("mobile.ngrok.loggedIn", { suffix: credential?.suffix ?? "" });

	const logIn = () => {
		if (ngrok.status?.apiKey?.present) {
			ngrok.mintCredential.mutate();
			return;
		}
		bridge.setTokenOpen(true);
	};

	const removeToken = () => {
		ngrok.removeAuthtoken.mutate(undefined, { onSuccess: () => setConfirmOpen(false) });
	};

	const error =
		(ngrok.mintCredential.error instanceof Error && ngrok.mintCredential.error.message) ||
		(ngrok.removeAuthtoken.error instanceof Error && ngrok.removeAuthtoken.error.message) ||
		null;

	return (
		<>
			<SettingsRow label={t("mobile.ngrok.credential")}>
				<div className="flex min-w-0 flex-1 flex-col items-end gap-2">
					<span className="max-w-full break-words text-right text-sm text-settings-muted">{value}</span>
					<div className="flex flex-wrap items-center justify-end gap-2">
						{!present && (
							<Button type="button" variant="footer" size="sm" onClick={logIn}>
								{t("mobile.ngrok.logIn")}
							</Button>
						)}
						{present && (
							<Button type="button" variant="footer" size="sm" onClick={() => bridge.setTokenOpen(true)}>
								{t("mobile.ngrok.replaceToken")}
							</Button>
						)}
						{source === "operator" && (
							<Button type="button" variant="footer" size="sm" onClick={() => setConfirmOpen(true)}>
								{t("mobile.ngrok.remove")}
							</Button>
						)}
						<Button
							type="button"
							variant="footer"
							size="sm"
							onClick={() => void operatorBridge.app.openExternal(NGROK_DASHBOARD_URL)}
						>
							{t("mobile.ngrok.openDashboard")}
						</Button>
					</div>
					{error && <p className="text-xs text-error">{error}</p>}
				</div>
			</SettingsRow>

			<Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
				<DialogContent>
					<DialogHeader>
						<DialogTitle>{t("mobile.ngrok.remove")}</DialogTitle>
						<DialogDescription>{t("mobile.ngrok.removeBody")}</DialogDescription>
					</DialogHeader>
					<DialogFooter>
						<Button type="button" variant="footer" onClick={() => setConfirmOpen(false)}>
							{t("blocks.cancel")}
						</Button>
						<Button type="button" onClick={removeToken} disabled={ngrok.removeAuthtoken.isPending}>
							{t("mobile.ngrok.removeConfirm")}
						</Button>
					</DialogFooter>
				</DialogContent>
			</Dialog>
		</>
	);
}
