import * as Dialog from "@radix-ui/react-dialog";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { operatorBridge } from "../lib/bridge";
import type { UpdateSettings } from "../../shared/update-settings";
import { Button } from "./ui/button";
import {
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "./ui/dialog";

// UpdateOptInPrompt is the Tauri first-run auto-update opt-in. The Electron shell
// asked this once from the main process (auto-updater.ts ensureUpdatePrefs) when
// no settings file existed; in the ported shell updates live in shared daemon
// settings, so the equivalent one-time ask lives here: it shows only in the
// native shell, only while updates are still disabled-by-default, and only until
// the user answers once (the answer is remembered in webview localStorage and
// persisted through updateSettings.set). Dismissing counts as declining —
// matching Electron's "Not now" button.
export const UPDATE_OPT_IN_ASKED_KEY = "operator-update-opt-in-asked";

const DECLINED_SETTINGS: UpdateSettings = { enabled: false, channel: "latest", nightlyAck: false, feature: null };
const ENABLED_SETTINGS: UpdateSettings = { enabled: true, channel: "latest", nightlyAck: false, feature: null };

function tauriShellPresent(): boolean {
	return typeof window !== "undefined" && Boolean((window as { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__);
}

function alreadyAsked(): boolean {
	try {
		return window.localStorage.getItem(UPDATE_OPT_IN_ASKED_KEY) === "1";
	} catch {
		return false;
	}
}

export function UpdateOptInPrompt() {
	const { t } = useTranslation();
	const [answered, setAnswered] = useState(false);
	const query = useQuery({
		queryKey: ["update-opt-in"],
		queryFn: () => operatorBridge.updateSettings.get(),
		staleTime: Infinity,
		retry: false,
	});

	if (!tauriShellPresent() || answered || alreadyAsked()) return null;
	if (query.data?.enabled !== false) return null;

	const answer = async (settings: UpdateSettings) => {
		setAnswered(true);
		try {
			window.localStorage.setItem(UPDATE_OPT_IN_ASKED_KEY, "1");
		} catch {
			// Storage can be unavailable; the prompt then re-shows next launch,
			// which is the honest fallback for an unrecorded answer.
			return;
		}
		try {
			await operatorBridge.updateSettings.set(settings);
		} catch (error) {
			console.warn("Unable to persist the auto-update opt-in choice", error);
		}
	};

	return (
		<Dialog.Root open>
			<Dialog.Portal>
				<Dialog.Overlay className="dialog-overlay data-[state=open]:animate-overlay-in" />
				<Dialog.Content
					data-testid="updates-opt-in"
					className={`${settingsDialogContentClass} fixed left-1/2 top-1/2 w-dialog-lg -translate-x-1/2 -translate-y-1/2 data-[state=open]:animate-modal-in`}
				>
					<div className={settingsDialogHeaderClass}>
						<Dialog.Title className="settings-dialog-title">{t("settings.updates.optIn.title")}</Dialog.Title>
						<Dialog.Description className="text-control leading-body text-settings-muted">
							{t("settings.updates.optIn.body")}
						</Dialog.Description>
					</div>
					<div className={settingsDialogBodyClass}>
						<p className="text-caption text-settings-muted">{t("settings.updates.optIn.changeLater")}</p>
					</div>
					<div className={`${settingsDialogFooterClass} justify-end gap-3`}>
						<Button
							type="button"
							variant="footer"
							data-testid="updates-opt-in-decline"
							onClick={() => void answer(DECLINED_SETTINGS)}
						>
							{t("settings.updates.optIn.decline")}
						</Button>
						<Button
							type="button"
							variant="footer-primary"
							data-testid="updates-opt-in-accept"
							onClick={() => void answer(ENABLED_SETTINGS)}
						>
							{t("settings.updates.optIn.accept")}
						</Button>
					</div>
				</Dialog.Content>
			</Dialog.Portal>
		</Dialog.Root>
	);
}
