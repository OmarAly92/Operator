import { useTranslation } from "react-i18next";
import type { ThemePreference, ThemeStyle } from "../../lib/theme";
import { useUiStore } from "../../stores/ui-store";
import { TERMINAL_BACKGROUNDS, type TerminalBackground } from "../../lib/terminal-background";
import { TERMINAL_FONT_SIZES, clampTerminalFontSize } from "../../lib/terminal-font-size";
import { EXTERNAL_EDITORS, type OpenFilesIn } from "../../lib/open-files-in";
import { Switch } from "../ui/switch";
import { SettingsOptionMenu, type SettingsOption } from "./SettingsOptionMenu";
import { SettingsLinkRow, SettingsRow } from "./SettingsRow";
import { SettingsSection } from "./SettingsSection";

const COLOR_THEME_OPTIONS = [
	{ value: "warp", label: "Warp" },
	{ value: "orchestrate", label: "Orchestrate" },
	{ value: "github", label: "GitHub" },
	{ value: "catppuccin", label: "Catppuccin" },
	{ value: "dracula", label: "Dracula" },
	{ value: "tokyo-night", label: "Tokyo Night" },
	{ value: "rose-pine", label: "Rosé Pine" },
	{ value: "nord", label: "Nord" },
	{ value: "gruvbox", label: "Gruvbox" },
	{ value: "solarized", label: "Solarized" },
] satisfies SettingsOption<ThemeStyle>[];

function ColorChip({ color }: { color: string }) {
	return (
		<span
			aria-hidden="true"
			className="size-3.5 shrink-0 rounded-full border border-white/15"
			style={{ backgroundColor: color }}
		/>
	);
}

export function GeneralSettingsSection({
	onConnectMobile,
	titleHidden,
}: {
	onConnectMobile: () => void;
	titleHidden?: boolean;
}) {
	const { t } = useTranslation();
	const themePreference = useUiStore((state) => state.themePreference);
	const setThemePreference = useUiStore((state) => state.setThemePreference);
	const themeStyle = useUiStore((state) => state.themeStyle);
	const setThemeStyle = useUiStore((state) => state.setThemeStyle);
	const terminalBackground = useUiStore((state) => state.terminalBackground);
	const setTerminalBackground = useUiStore((state) => state.setTerminalBackground);
	const terminalFontSize = useUiStore((state) => state.terminalFontSize);
	const setTerminalFontSize = useUiStore((state) => state.setTerminalFontSize);
	const terminalSecretRedaction = useUiStore((state) => state.terminalSecretRedaction);
	const setTerminalSecretRedaction = useUiStore((state) => state.setTerminalSecretRedaction);
	const terminalPredictiveEcho = useUiStore((state) => state.terminalPredictiveEcho);
	const setTerminalPredictiveEcho = useUiStore((state) => state.setTerminalPredictiveEcho);
	const openFilesIn = useUiStore((state) => state.openFilesIn);
	const setOpenFilesIn = useUiStore((state) => state.setOpenFilesIn);

	const themeOptions = [
		{ value: "light", label: t("settings.theme.light") },
		{ value: "dark", label: t("settings.theme.dark") },
		{
			value: "system",
			label: t("settings.theme.system"),
		},
	] satisfies SettingsOption<ThemePreference>[];

	const terminalColorOptions = TERMINAL_BACKGROUNDS.map((option) => ({
		value: option.id,
		label: t(option.labelKey),
		icon: <ColorChip color={option.color} />,
	})) satisfies SettingsOption<TerminalBackground>[];

	const openFilesInOptions = [
		{ value: "system", label: t("settings.openFilesIn.system") },
		...EXTERNAL_EDITORS,
	] satisfies SettingsOption<OpenFilesIn>[];

	const terminalFontSizeOptions = TERMINAL_FONT_SIZES.map((size) => ({
		value: String(size),
		label: t("settings.terminalFontSize.value", { size }),
	})) satisfies SettingsOption<string>[];

	return (
		<SettingsSection title={t("settings.general")} titleHidden={titleHidden} grouped>
			<SettingsRow label={t("settings.colorTheme")}>
				<SettingsOptionMenu
					aria-label={t("settings.colorTheme")}
					value={themeStyle}
					options={COLOR_THEME_OPTIONS}
					onChange={setThemeStyle}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.terminalColor")}>
				<SettingsOptionMenu
					aria-label={t("settings.terminalColor")}
					value={terminalBackground}
					options={terminalColorOptions}
					onChange={setTerminalBackground}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.theme")}>
				<SettingsOptionMenu
					aria-label={t("settings.theme")}
					value={themePreference}
					options={themeOptions}
					onChange={setThemePreference}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.terminalFontSize")}>
				<SettingsOptionMenu
					aria-label={t("settings.terminalFontSize")}
					value={String(terminalFontSize)}
					options={terminalFontSizeOptions}
					onChange={(next) => setTerminalFontSize(clampTerminalFontSize(Number(next)))}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.terminalSecretRedaction")}>
				<Switch
					aria-label={t("settings.terminalSecretRedaction")}
					checked={terminalSecretRedaction}
					onCheckedChange={setTerminalSecretRedaction}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.terminalPredictiveEcho")}>
				<Switch
					aria-label={t("settings.terminalPredictiveEcho")}
					checked={terminalPredictiveEcho}
					onCheckedChange={setTerminalPredictiveEcho}
				/>
			</SettingsRow>
			<SettingsRow label={t("settings.openFilesIn")}>
				<SettingsOptionMenu
					aria-label={t("settings.openFilesIn")}
					value={openFilesIn}
					options={openFilesInOptions}
					onChange={setOpenFilesIn}
				/>
			</SettingsRow>
			<SettingsLinkRow label={t("settings.connectMobile")} onClick={onConnectMobile} />
		</SettingsSection>
	);
}
