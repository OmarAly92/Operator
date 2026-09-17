import { useNavigate } from "@tanstack/react-router";
import { Ellipsis } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	claudeAccountPlanLabel,
	claudeAccountSlug,
	type ClaudeAccount,
	sharedClaudeLogins,
	useClaudeAccountLogin,
	useClaudeAccounts,
	useCreateClaudeAccount,
	useDeleteClaudeAccount,
	usePreferClaudeAccount,
	useRefreshClaudeAccounts,
	useRelinkClaudeAccount,
	useRenameClaudeAccount,
} from "../../hooks/useClaudeAccounts";
import { apiErrorMessage } from "../../lib/api-client";
import { useUiStore } from "../../stores/ui-store";
import { Badge } from "../ui/badge";
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
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "../ui/dropdown-menu";
import { SettingsSection } from "./SettingsSection";

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
	const prefer = usePreferClaudeAccount();
	const [adding, setAdding] = useState(false);
	const [label, setLabel] = useState("");
	const [pendingRemove, setPendingRemove] = useState<ClaudeAccount | null>(null);
	const [renaming, setRenaming] = useState<{ id: string; label: string } | null>(null);
	const [error, setError] = useState<string | null>(null);

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
	const sharedLogins = sharedClaudeLogins(accounts);
	const slug = claudeAccountSlug(label);

	return (
		<SettingsSection title={t("settings.claudeAccounts.title")} titleHidden={titleHidden} sectionId="claude-accounts">
			{accountsQuery.error ? <p className="px-3 text-caption text-destructive">{t("settings.claudeAccounts.loadFailed")}</p> : null}
			{accounts.map((account) => {
				const planLabel = claudeAccountPlanLabel(account, t);
				const replaced = Object.entries(account.sharedSetup ?? {})
					.filter(([, state]) => state === "replaced")
					.map(([name]) => name)
					.sort();
				const sameLoginAs = sharedLogins.get(account.id);
				const isRenaming = renaming?.id === account.id;
				const menuAction = (fn: () => Promise<unknown>) => () => {
					setError(null);
					void fn().catch((err) => setError(errorText(err)));
				};
				return (
					<div key={account.id} data-testid={`claude-account-${account.id}`} className="settings-row-bar h-auto min-h-0 flex-col items-stretch gap-1 px-3 py-2.5">
						<div className="flex min-w-0 items-center gap-2">
							{isRenaming ? (
								<form
									className="flex items-center gap-1.5"
									onSubmit={(event) => {
										event.preventDefault();
										void submitRename();
									}}
								>
									<Input
										aria-label={t("settings.claudeAccounts.labelField")}
										value={renaming.label}
										onChange={(event) => setRenaming({ id: account.id, label: event.target.value })}
										className="h-control-md max-w-44 text-sm"
										autoFocus
									/>
									<Button type="submit" size="sm" disabled={rename.isPending}>
										{t("settings.claudeAccounts.save")}
									</Button>
									<Button type="button" size="sm" variant="ghost" onClick={() => setRenaming(null)}>
										{t("settings.claudeAccounts.cancel")}
									</Button>
								</form>
							) : (
								<span className="truncate text-sm font-medium text-settings-label">{account.label}</span>
							)}
							<span className="flex shrink-0 items-center gap-1">
								{account.isDefault ? <Badge variant="outline">{t("settings.claudeAccounts.default")}</Badge> : null}
								<Badge variant="outline">{planLabel}</Badge>
								{account.isPreferred ? <Badge variant="accent">{t("settings.claudeAccounts.preferred")}</Badge> : null}
							</span>
							<div className="ml-auto flex shrink-0 items-center gap-1">
								{!account.isPreferred ? (
									<Button
										type="button"
										size="sm"
										variant="outline"
										onClick={menuAction(() => prefer.mutateAsync(account.id))}
										disabled={prefer.isPending}
									>
										{t("settings.claudeAccounts.prefer")}
									</Button>
								) : null}
								<DropdownMenu>
									<DropdownMenuTrigger asChild>
										<Button type="button" size="icon-sm" variant="ghost" aria-label={t("settings.claudeAccounts.actions", { label: account.label })}>
											<Ellipsis aria-hidden="true" className="size-4" />
										</Button>
									</DropdownMenuTrigger>
									<DropdownMenuContent align="end">
										<DropdownMenuItem onSelect={() => void openLogin(account.id)} disabled={login.isPending}>
											{account.status?.loggedIn ? t("settings.claudeAccounts.loginAgain") : t("settings.claudeAccounts.login")}
										</DropdownMenuItem>
										{!account.isDefault ? (
											<DropdownMenuItem onSelect={() => setRenaming({ id: account.id, label: account.label })}>
												{t("settings.claudeAccounts.rename")}
											</DropdownMenuItem>
										) : null}
										{replaced.length > 0 ? (
											<DropdownMenuItem onSelect={menuAction(() => relink.mutateAsync(account.id))}>
												{t("settings.claudeAccounts.relink")}
											</DropdownMenuItem>
										) : null}
										{!account.isDefault ? (
											<>
												<DropdownMenuSeparator />
												<DropdownMenuItem className="text-destructive focus:text-destructive" onSelect={() => setPendingRemove(account)}>
													{t("settings.claudeAccounts.remove")}
												</DropdownMenuItem>
											</>
										) : null}
									</DropdownMenuContent>
								</DropdownMenu>
							</div>
						</div>
						<div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-0.5 text-caption text-settings-muted">
							<span className="truncate font-mono">{account.configDir}</span>
							{account.status?.reportedEmail ? <span className="truncate">{account.status.reportedEmail}</span> : null}
						</div>
						{sameLoginAs ? (
							<p className="text-caption text-warning">{t("settings.claudeAccounts.sameLogin", { labels: sameLoginAs.join(", ") })}</p>
						) : null}
						{replaced.length > 0 ? (
							<div className="flex items-center gap-2 text-caption text-warning">
								<span>{t("settings.claudeAccounts.setupReplaced", { items: replaced.join(", ") })}</span>
								<button
									type="button"
									className="underline underline-offset-2 hover:text-foreground"
									onClick={menuAction(() => relink.mutateAsync(account.id))}
								>
									{t("settings.claudeAccounts.relink")}
								</button>
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
