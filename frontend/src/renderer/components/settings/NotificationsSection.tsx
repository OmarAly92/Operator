import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { operatorBridge } from "../../lib/bridge";
import { formatTimeCompact } from "../../lib/format-time";
import { usePhoneAlerts, useTestPhoneAlert } from "../../hooks/usePhoneAlerts";
import { Button } from "../ui/button";
import { SettingsRow } from "./SettingsRow";
import { SettingsSection } from "./SettingsSection";

type Permission = "authorized" | "denied" | "not_determined" | "unsupported";

const PERMISSION_DENIED_PREFIX = "notification_permission=denied";

export function NotificationsSection({ titleHidden }: { titleHidden?: boolean } = {}) {
	const { t } = useTranslation();
	const [permission, setPermission] = useState<Permission | undefined>(undefined);
	const [macTestError, setMacTestError] = useState<string | null>(null);
	const phone = usePhoneAlerts();
	const testPhone = useTestPhoneAlert();

	useEffect(() => {
		operatorBridge.notifications
			.permission()
			.then(setPermission)
			.catch((error: unknown) => {
				console.warn("Unable to read the macOS notification permission", error);
				setPermission("unsupported");
			});
	}, []);

	const sendMacTest = () => {
		setMacTestError(null);
		operatorBridge.notifications
			.show({
				id: `test:${Date.now()}`,
				title: t("settings.notifications.testTitle"),
				body: t("settings.notifications.testBody"),
				type: "test",
			})
			.catch((error: unknown) => {
				const message = error instanceof Error ? error.message : String(error);
				if (message.startsWith(PERMISSION_DENIED_PREFIX)) {
					setPermission("denied");
				} else {
					setMacTestError(message);
				}
			});
	};

	const status = phone.data;
	const phoneLine = phone.isLoading
		? null
		: phone.isError
			? t("settings.notifications.phoneLoadFailed")
			: !status?.enabled
				? t("settings.notifications.phoneOff")
				: !status.claimed
					? t("settings.notifications.phoneWaiting")
					: status.lastDelivery && !status.lastDelivery.ok
						? t("settings.notifications.phoneFailed", { error: status.lastDelivery.error })
						: status.lastDelivery
							? t("settings.notifications.phoneOnWithDelivery", { time: formatTimeCompact(status.lastDelivery.at) })
							: t("settings.notifications.phoneOn");

	return (
		<SettingsSection title={t("settings.notifications.title")} titleHidden={titleHidden} grouped>
			<SettingsRow label={t("settings.notifications.mac")}>
				<span>{t(`settings.notifications.permission.${permission ?? "checking"}`)}</span>
				{permission === "denied" ? (
					<Button variant="outline" size="sm" onClick={() => void operatorBridge.notifications.openSettings()}>
						{t("settings.notifications.openSystemSettings")}
					</Button>
				) : null}
			</SettingsRow>
			<SettingsRow label={t("settings.notifications.testMac")}>
				<Button variant="outline" size="sm" onClick={sendMacTest}>
					{t("settings.notifications.send")}
				</Button>
			</SettingsRow>
			{macTestError ? <p className="px-1 text-xs text-error">{macTestError}</p> : null}
			<SettingsRow label={t("settings.notifications.phone")}>
				<span>{phoneLine}</span>
			</SettingsRow>
			<SettingsRow label={t("settings.notifications.testPhone")}>
				<Button
					variant="outline"
					size="sm"
					disabled={!status?.enabled || !status.claimed || testPhone.isPending}
					onClick={() => testPhone.mutate()}
				>
					{t("settings.notifications.send")}
				</Button>
			</SettingsRow>
		</SettingsSection>
	);
}
