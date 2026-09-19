import { useState } from "react";
import { useTranslation } from "react-i18next";

import { operatorBridge } from "../../../lib/bridge";
import { SettingsRow } from "../SettingsRow";
import { Badge } from "../../ui/badge";
import { Button } from "../../ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../../ui/select";
import { NgrokApiKeyDialog } from "../NgrokApiKeyDialog";
import type { MobileBridge } from "./useMobileBridge";
import type { Ngrok } from "./useNgrok";

const NGROK_DOMAINS_URL = "https://dashboard.ngrok.com/domains";
const NO_DOMAIN_VALUE = "__none";

interface NgrokApiKeyCardProps {
	bridge: MobileBridge;
	ngrok: Ngrok;
}

export function NgrokApiKeyCard({ ngrok }: NgrokApiKeyCardProps) {
	const { t } = useTranslation();
	const [dialogOpen, setDialogOpen] = useState(false);

	const present = ngrok.status?.apiKey?.present ?? false;
	const account = ngrok.account;
	const domain = ngrok.status?.domain ?? "";

	const saveKey = async (key: string) => {
		await ngrok.setApiKey.mutateAsync(key);
	};

	return (
		<>
			<SettingsRow label={t("mobile.ngrok.apiKey")}>
				<div className="flex min-w-0 flex-1 flex-col items-end gap-2">
					<div className="flex items-center gap-2">
						<span className="text-sm text-settings-muted">
							{present ? t("mobile.ngrok.apiKeySet") : t("mobile.ngrok.apiKeyMissing")}
						</span>
						{!present && (
							<Button type="button" variant="footer" size="sm" onClick={() => setDialogOpen(true)}>
								{t("mobile.ngrok.addKey")}
							</Button>
						)}
						{present && (
							<>
								<Button type="button" variant="footer" size="sm" onClick={() => setDialogOpen(true)}>
									{t("mobile.ngrok.replace")}
								</Button>
								<Button type="button" variant="footer" size="sm" onClick={() => ngrok.removeApiKey.mutate()}>
									{t("mobile.ngrok.remove")}
								</Button>
							</>
						)}
					</div>
					{account && !account.valid && <p className="text-xs text-error">{account.error}</p>}
				</div>
			</SettingsRow>

			{account?.valid && (
				<>
					<SettingsRow label={t("mobile.ngrok.stableDomain")}>
						{account.reservedDomains.length === 0 ? (
							<div className="flex items-center gap-2">
								<span className="text-caption text-settings-muted">{t("mobile.ngrok.noReservedDomains")}</span>
								<Button
									type="button"
									variant="footer"
									size="sm"
									onClick={() => void operatorBridge.app.openExternal(NGROK_DOMAINS_URL)}
								>
									{t("mobile.ngrok.openDashboard")}
								</Button>
							</div>
						) : (
							<Select
								value={domain === "" ? NO_DOMAIN_VALUE : domain}
								onValueChange={(value) => ngrok.setDomain.mutate(value === NO_DOMAIN_VALUE ? "" : value)}
							>
								<SelectTrigger aria-label={t("mobile.ngrok.stableDomain")}>
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value={NO_DOMAIN_VALUE}>{t("mobile.ngrok.noDomain")}</SelectItem>
									{account.reservedDomains.map((reservedDomain) => (
										<SelectItem key={reservedDomain.id} value={reservedDomain.domain}>
											{reservedDomain.domain}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						)}
					</SettingsRow>

					<SettingsRow label={t("mobile.ngrok.authtokens")}>
						<div className="flex min-w-0 flex-1 flex-col items-end gap-2">
							{account.credentials.length === 0 ? (
								<span className="text-caption text-settings-muted">{t("mobile.ngrok.none")}</span>
							) : (
								account.credentials.map((credential) => (
									<div key={credential.id} className="flex w-full items-center justify-end gap-2">
										<span className="text-sm text-settings-label">{credential.description}</span>
										<span className="text-caption text-settings-muted">
											{new Date(credential.createdAt).toLocaleDateString()}
										</span>
										{credential.isOperator && <Badge variant="neutral">{t("mobile.ngrok.thisApp")}</Badge>}
										<Button
											type="button"
											variant="footer"
											size="sm"
											onClick={() => ngrok.revokeCredential.mutate(credential.id)}
										>
											{t("mobile.ngrok.revoke")}
										</Button>
									</div>
								))
							)}
						</div>
					</SettingsRow>

					<SettingsRow label={t("mobile.ngrok.sessions")}>
						<div className="flex min-w-0 flex-1 flex-col items-end gap-2">
							{account.sessions.length === 0 ? (
								<span className="text-caption text-settings-muted">{t("mobile.ngrok.none")}</span>
							) : (
								account.sessions.map((session) => (
									<div key={session.id} className="flex w-full flex-col items-end gap-1">
										<div className="flex items-center gap-2">
											<span className="text-sm text-settings-label">
												{session.region} · {session.ip} · {session.agentVersion} · {session.os}
											</span>
											{session.isThisMachine && <Badge variant="neutral">{t("mobile.ngrok.thisMachine")}</Badge>}
										</div>
										<span className="text-caption text-settings-muted">
											{new Date(session.startedAt).toLocaleTimeString()}
										</span>
									</div>
								))
							)}
						</div>
					</SettingsRow>

					<SettingsRow label={t("mobile.ngrok.endpoints")}>
						<div className="flex min-w-0 flex-1 flex-col items-end gap-1">
							{account.endpoints.length === 0 ? (
								<span className="text-caption text-settings-muted">{t("mobile.ngrok.none")}</span>
							) : (
								account.endpoints.map((endpoint) => (
									<div key={endpoint.id} className="flex items-center gap-2">
										<span className="tracking-settings-mono break-all text-settings-label">{endpoint.publicUrl}</span>
										<span className="text-caption text-settings-muted">{endpoint.proto}</span>
									</div>
								))
							)}
						</div>
					</SettingsRow>
				</>
			)}

			<NgrokApiKeyDialog open={dialogOpen} onOpenChange={setDialogOpen} onSave={saveKey} />
		</>
	);
}
