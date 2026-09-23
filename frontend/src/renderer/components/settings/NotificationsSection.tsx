import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { operatorBridge } from "../../lib/bridge";
import { formatTimeCompact } from "../../lib/format-time";
import { usePhoneAlerts, useTestPhoneAlert } from "../../hooks/usePhoneAlerts";
import { Button } from "../ui/button";
import { SettingsRow } from "./SettingsRow";
import { SettingsSection } from "./SettingsSection";

type Permission = "authorized" | "denied" | "not_determined" | "unsupported";

const PERMISSION_ERROR_PATTERN = /^notification_permission=([a-z_]+):/;

function permissionFromError(message: string): Permission | null {
	const match = PERMISSION_ERROR_PATTERN.exec(message);
	if (!match) return null;
	const state = match[1];
	if (state === "authorized" || state === "denied" || state === "not_determined" || state === "unsupported") {
		return state;
	}
	return null;
}

export function NotificationsSection({ titleHidden }: { titleHidden?: boolean } = {}) {
	const { t } = useTranslation();
	const [permission, setPermission] = useState<Permission | undefined>(undefined);
	const [macTestError, setMacTestError] = useState<string | null>(null);
	const [macTestBlocked, setMacTestBlocked] = useState(false);
	const phone = usePhoneAlerts();
	const testPhone = useTestPhoneAlert();

	const refreshPermission = () => {
		operatorBridge.notifications
			.permission()
			.then(setPermission)
			.catch((error: unknown) => {
				console.warn("Unable to read the macOS notification permission", error);
				setPermission("unsupported");
			});
	};

	useEffect(() => {
		refreshPermission();
	}, []);

	useEffect(() => {
		const onFocus = () => refreshPermission();
		const onVisibilityChange = () => {
			if (document.visibilityState === "visible") refreshPermission();
		};
		window.addEventListener("focus", onFocus);
		document.addEventListener("visibilitychange", onVisibilityChange);
		return () => {
			window.removeEventListener("focus", onFocus);
			document.removeEventListener("visibilitychange", onVisibilityChange);
		};
	}, []);

	const sendMacTest = () => {
		setMacTestError(null);
		setMacTestBlocked(false);
		operatorBridge.notifications
			.show({
				id: `test:${Date.now()}`,
				title: t("settings.notifications.testTitle"),
				body: t("settings.notifications.testBody"),
				type: "test",
			})
			.catch((error: unknown) => {
				const message = error instanceof Error ? error.message : String(error);
				const state = permissionFromError(message);
				if (state && state !== "authorized") {
					setPermission(state);
					setMacTestBlocked(true);
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
				{permission === "denied" || permission === "not_determined" ? (
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
			{macTestBlocked ? (
				<p className="px-1 text-xs text-error">{t("settings.notifications.macPermissionBlocked")}</p>
			) : macTestError ? (
				<p className="px-1 text-xs text-error">{macTestError}</p>
			) : null}
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
