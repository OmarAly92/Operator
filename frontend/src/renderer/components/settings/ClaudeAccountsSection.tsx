import { useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	claudeAccountPlanKey,
	claudeAccountSlug,
	type ClaudeAccount,
	useClaudeAccountLogin,
	useClaudeAccounts,
	useCreateClaudeAccount,
	useDeleteClaudeAccount,
	useRefreshClaudeAccounts,
	useRelinkClaudeAccount,
	useRenameClaudeAccount,
} from "../../hooks/useClaudeAccounts";
import { apiErrorMessage } from "../../lib/api-client";
import { useUiStore } from "../../stores/ui-store";
import { Button } from "../ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogTitle,
	settingsDialogBodyClass,
	settingsDialogContentClass,
	settingsDialogFooterClass,
	settingsDialogHeaderClass,
} from "../ui/dialog";
import { Input } from "../ui/input";
import { SettingsSection } from "./SettingsSection";

const PLAN_KEYS = {
	max: "settings.claudeAccounts.plan.max",
	pro: "settings.claudeAccounts.plan.pro",
	notLoggedIn: "settings.claudeAccounts.plan.notLoggedIn",
	unknown: "settings.claudeAccounts.plan.unknown",
} as const;

function errorText(error: unknown): string {
	if (error && typeof error === "object" && "message" in error && typeof error.message === "string") {
		return error.message;
	}
	return apiErrorMessage(error);
}

export function ClaudeAccountsSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const closeSettings = useUiStore((state) => state.closeSettings);
	const setActiveShellTerminal = useUiStore((state) => state.setActiveShellTerminal);
	const accountsQuery = useClaudeAccounts();
	const refreshAccounts = useRefreshClaudeAccounts();
	const createAccount = useCreateClaudeAccount();
	const login = useClaudeAccountLogin();
	const removeAccount = useDeleteClaudeAccount();
	const relink = useRelinkClaudeAccount();
	const rename = useRenameClaudeAccount();
	const [adding, setAdding] = useState(false);
	const [label, setLabel] = useState("");
	const [pendingRemove, setPendingRemove] = useState<ClaudeAccount | null>(null);
	const [renaming, setRenaming] = useState<{ id: string; label: string } | null>(null);
	const [error, setError] = useState<string | null>(null);

	useEffect(() => {
		const onFocus = () => void refreshAccounts();
		window.addEventListener("focus", onFocus);
		return () => window.removeEventListener("focus", onFocus);
	}, [refreshAccounts]);

	useEffect(() => {
		void refreshAccounts();
	}, [refreshAccounts]);

	const openLogin = async (id: string) => {
		setError(null);
		try {
			const shell = await login.mutateAsync(id);
			closeSettings();
			setActiveShellTerminal(shell.handleId);
			void navigate({ to: "/terminals" });
		} catch (err) {
			setError(errorText(err));
		}
	};

	const submitAdd = async () => {
		setError(null);
		try {
			const account = await createAccount.mutateAsync(label);
			setAdding(false);
			setLabel("");
			await openLogin(account.id);
		} catch (err) {
			setError(errorText(err));
		}
	};

	const confirmRemove = async () => {
		if (!pendingRemove) return;
		setError(null);
		try {
			await removeAccount.mutateAsync(pendingRemove.id);
			setPendingRemove(null);
		} catch (err) {
			setPendingRemove(null);
			setError(errorText(err));
		}
	};

	const submitRename = async () => {
		if (!renaming) return;
		setError(null);
		try {
			await rename.mutateAsync(renaming);
			setRenaming(null);
		} catch (err) {
			setError(errorText(err));
		}
	};

	const accounts = accountsQuery.data ?? [];
	const slug = claudeAccountSlug(label);

	return (
		<SettingsSection title={t("settings.claudeAccounts.title")} titleHidden={titleHidden} sectionId="claude-accounts">
			{accountsQuery.error ? <p className="px-3 text-caption text-destructive">{t("settings.claudeAccounts.loadFailed")}</p> : null}
			{accounts.map((account) => {
				const planKey = claudeAccountPlanKey(account);
				const planLabel = planKey === "other" ? (account.status?.subscriptionType ?? "") : t(PLAN_KEYS[planKey]);
				const replaced = Object.entries(account.sharedSetup ?? {})
					.filter(([, state]) => state === "replaced")
					.map(([name]) => name)
					.sort();
				const isRenaming = renaming?.id === account.id;
				return (
					<div key={account.id} data-testid={`claude-account-${account.id}`} className="settings-row-bar flex-col items-stretch gap-1.5">
						<div className="flex min-w-0 items-center gap-2">
							{isRenaming ? (
								<Input
									aria-label={t("settings.claudeAccounts.labelField")}
									value={renaming.label}
									onChange={(event) => setRenaming({ id: account.id, label: event.target.value })}
									className="max-w-48"
								/>
							) : (
								<span className="truncate text-sm text-settings-label">{account.label}</span>
							)}
							{account.isDefault ? (
								<span className="rounded px-1.5 text-micro text-settings-muted ring-1 ring-border">{t("settings.claudeAccounts.default")}</span>
							) : null}
							<span className="rounded px-1.5 text-micro text-settings-muted ring-1 ring-border">{planLabel}</span>
							<div className="ml-auto flex shrink-0 items-center gap-1.5">
								<Button type="button" variant="outline" onClick={() => void openLogin(account.id)} disabled={login.isPending}>
									{account.status?.loggedIn ? t("settings.claudeAccounts.loginAgain") : t("settings.claudeAccounts.login")}
								</Button>
								{!account.isDefault && !isRenaming ? (
									<Button type="button" variant="outline" onClick={() => setRenaming({ id: account.id, label: account.label })}>
										{t("settings.claudeAccounts.rename")}
									</Button>
								) : null}
								{isRenaming ? (
									<Button type="button" variant="outline" onClick={() => void submitRename()} disabled={rename.isPending}>
										{t("settings.claudeAccounts.save")}
									</Button>
								) : null}
								{!account.isDefault ? (
									<Button type="button" variant="outline" onClick={() => setPendingRemove(account)}>
										{t("settings.claudeAccounts.remove")}
									</Button>
								) : null}
							</div>
						</div>
						<span className="truncate font-mono text-md-sm text-settings-muted">{account.configDir}</span>
						{account.status?.reportedEmail ? (
							<span className="truncate text-caption text-settings-muted">
								{t("settings.claudeAccounts.reportedEmail", { email: account.status.reportedEmail })}
							</span>
						) : null}
						{replaced.length > 0 ? (
							<div className="flex items-center gap-2 text-caption text-warning">
								<span>{t("settings.claudeAccounts.setupReplaced", { items: replaced.join(", ") })}</span>
								<Button
									type="button"
									variant="outline"
									onClick={() => void relink.mutateAsync(account.id).catch((err) => setError(errorText(err)))}
								>
									{t("settings.claudeAccounts.relink")}
								</Button>
							</div>
						) : null}
					</div>
				);
			})}
			{error ? <p className="px-3 text-caption text-destructive">{error}</p> : null}
			<p className="px-3 text-caption text-settings-muted">{t("settings.claudeAccounts.mcpNote")}</p>
			<div className="px-3">
				<Button type="button" variant="outline" onClick={() => setAdding(true)}>
					{t("settings.claudeAccounts.add")}
				</Button>
			</div>

			<Dialog open={adding} onOpenChange={setAdding}>
				<DialogContent className={settingsDialogContentClass}>
					<form
						className="contents"
						onSubmit={(event) => {
							event.preventDefault();
							void submitAdd();
						}}
					>
						<div className={settingsDialogHeaderClass}>
							<DialogTitle>{t("settings.claudeAccounts.addTitle")}</DialogTitle>
							<DialogDescription>{slug ? t("settings.claudeAccounts.folderPreview", { path: `~/.claude-${slug}` }) : null}</DialogDescription>
						</div>
						<div className={settingsDialogBodyClass}>
							<label className="settings-field-label" htmlFor="claude-account-label">
								{t("settings.claudeAccounts.labelField")}
							</label>
							<Input id="claude-account-label" value={label} maxLength={32} onChange={(event) => setLabel(event.target.value)} autoFocus />
						</div>
						<div className={settingsDialogFooterClass}>
							<Button type="button" variant="outline" onClick={() => setAdding(false)}>
								{t("settings.claudeAccounts.cancel")}
							</Button>
							<Button type="submit" disabled={!slug || createAccount.isPending}>
								{t("settings.claudeAccounts.create")}
							</Button>
						</div>
					</form>
				</DialogContent>
			</Dialog>

			<Dialog open={pendingRemove !== null} onOpenChange={(open) => !open && setPendingRemove(null)}>
				<DialogContent className={settingsDialogContentClass}>
					<div className={settingsDialogHeaderClass}>
						<DialogTitle>{t("settings.claudeAccounts.removeTitle", { label: pendingRemove?.label ?? "" })}</DialogTitle>
						<DialogDescription>{t("settings.claudeAccounts.removeBody", { path: pendingRemove?.configDir ?? "" })}</DialogDescription>
					</div>
					<div className={settingsDialogFooterClass}>
						<Button type="button" variant="outline" onClick={() => setPendingRemove(null)}>
							{t("settings.claudeAccounts.cancel")}
						</Button>
						<Button type="button" onClick={() => void confirmRemove()} disabled={removeAccount.isPending}>
							{t("settings.claudeAccounts.remove")}
						</Button>
					</div>
				</DialogContent>
			</Dialog>
		</SettingsSection>
	);
}
