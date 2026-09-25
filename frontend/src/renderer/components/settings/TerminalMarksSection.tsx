import { Plus, Trash2 } from "lucide-react";
import { Fragment } from "react";
import { useTranslation } from "react-i18next";
import { warpDarkTheme } from "@operator/terminal-react";
import type { MessageKey } from "../../i18n/messages";
import {
	MAX_TERMINAL_MARK_PATTERN,
	MAX_TERMINAL_MARKS,
	TERMINAL_MARK_COLOURS,
	newTerminalMark,
	terminalMarkPatternValid,
	type TerminalMark,
	type TerminalMarkColour,
} from "../../lib/terminal-marks";
import { useUiStore } from "../../stores/ui-store";
import { Button } from "../ui/button";
import { Input } from "../ui/input";
import { SettingsOptionMenu, type SettingsOption } from "./SettingsOptionMenu";
import { SettingsSection } from "./SettingsSection";

const COLOUR_LABELS: Record<TerminalMarkColour, MessageKey> = {
	yellow: "settings.terminalMarks.colour.yellow",
	red: "settings.terminalMarks.colour.red",
	green: "settings.terminalMarks.colour.green",
	cyan: "settings.terminalMarks.colour.cyan",
	magenta: "settings.terminalMarks.colour.magenta",
};

function Swatch({ ansi }: { ansi: number }) {
	return (
		<span
			aria-hidden="true"
			className="size-3.5 shrink-0 rounded-full border border-white/15"
			style={{ backgroundColor: warpDarkTheme.ansi[ansi] }}
		/>
	);
}

export function TerminalMarksSection({ titleHidden }: { titleHidden?: boolean }) {
	const { t } = useTranslation();
	const marks = useUiStore((state) => state.terminalMarks);
	const setMarks = useUiStore((state) => state.setTerminalMarks);
	const update = (id: string, patch: Partial<Omit<TerminalMark, "id">>) =>
		setMarks(marks.map((mark) => (mark.id === id ? { ...mark, ...patch } : mark)));
	const colourOptions = TERMINAL_MARK_COLOURS.map((colour) => ({
		value: colour.id,
		label: t(COLOUR_LABELS[colour.id]),
		icon: <Swatch ansi={colour.ansi} />,
	})) satisfies SettingsOption<TerminalMarkColour>[];

	return (
		<SettingsSection title={t("settings.terminalMarks")} titleHidden={titleHidden} grouped>
			<div className="settings-row-bar">
				<span className="text-sm leading-5 text-settings-muted">
					{marks.length === 0 ? t("settings.terminalMarks.empty") : t("settings.terminalMarks.hint")}
				</span>
			</div>
			{marks.map((mark, index) => {
				const invalid = !terminalMarkPatternValid(mark.pattern, mark.regex);
				const position = index + 1;
				return (
					<Fragment key={mark.id}>
						<div className="settings-row-bar gap-2" data-testid="terminal-mark-row">
							<Input
								aria-label={t("settings.terminalMarks.pattern", { index: position })}
								aria-invalid={invalid || undefined}
								className="min-w-0 flex-1 font-mono"
								maxLength={MAX_TERMINAL_MARK_PATTERN}
								placeholder={t("settings.terminalMarks.placeholder")}
								spellCheck={false}
								value={mark.pattern}
								onChange={(event) => update(mark.id, { pattern: event.target.value })}
							/>
							<Button
								type="button"
								variant={mark.regex ? "secondary" : "ghost"}
								size="sm"
								className="font-mono"
								aria-label={t("settings.terminalMarks.regex")}
								aria-pressed={mark.regex}
								title={t("settings.terminalMarks.regex")}
								onClick={() => update(mark.id, { regex: !mark.regex })}
							>
								.*
							</Button>
							<SettingsOptionMenu
								aria-label={t("settings.terminalMarks.colour", { index: position })}
								value={mark.colour}
								options={colourOptions}
								onChange={(colour) => update(mark.id, { colour })}
							/>
							<Button
								type="button"
								variant="ghost"
								size="icon-sm"
								aria-label={t("settings.terminalMarks.remove", { index: position })}
								onClick={() => setMarks(marks.filter((entry) => entry.id !== mark.id))}
							>
								<Trash2 aria-hidden="true" />
							</Button>
						</div>
						{invalid ? (
							<p role="alert" className="px-3 pb-2 text-xs leading-4 text-destructive">
								{t("settings.terminalMarks.invalid")}
							</p>
						) : null}
					</Fragment>
				);
			})}
			{marks.length < MAX_TERMINAL_MARKS ? (
				<div className="settings-row-bar">
					<Button type="button" variant="ghost" size="sm" onClick={() => setMarks([...marks, newTerminalMark(marks)])}>
						<Plus aria-hidden="true" />
						{t("settings.terminalMarks.add")}
					</Button>
				</div>
			) : null}
		</SettingsSection>
	);
}
