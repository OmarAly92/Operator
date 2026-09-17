import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test } from "vitest";
import { useUiStore } from "../../stores/ui-store";
import { GeneralSettingsSection } from "./GeneralSettingsSection";

afterEach(() => {
	useUiStore.setState({ terminalFontSize: 14 });
	window.localStorage.clear();
});

test("terminal font size row shows the current size and updates the store", async () => {
	render(<GeneralSettingsSection onConnectMobile={() => {}} />);
	const trigger = screen.getByRole("button", { name: "Terminal Font Size" });
	expect(trigger).toHaveTextContent("14 px");
	await userEvent.click(trigger);
	await userEvent.click(await screen.findByRole("menuitem", { name: "16 px" }));
	expect(useUiStore.getState().terminalFontSize).toBe(16);
	expect(screen.getByRole("button", { name: "Terminal Font Size" })).toHaveTextContent("16 px");
});
