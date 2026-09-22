import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test } from "vitest";
import { useUiStore } from "../../stores/ui-store";
import { GeneralSettingsSection } from "./GeneralSettingsSection";

afterEach(() => {
	useUiStore.setState({ terminalFontSize: 14, openFilesIn: "system" });
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

test("open files in row shows the chosen editor and persists a new choice", async () => {
	render(<GeneralSettingsSection onConnectMobile={() => {}} />);
	const trigger = screen.getByRole("button", { name: "Open files in" });
	expect(trigger).toHaveTextContent("System default");
	await userEvent.click(trigger);
	await userEvent.click(await screen.findByRole("menuitem", { name: "Zed" }));
	expect(useUiStore.getState().openFilesIn).toBe("zed");
	expect(window.localStorage.getItem("opr.openFilesIn")).toBe("zed");
	expect(screen.getByRole("button", { name: "Open files in" })).toHaveTextContent("Zed");
});
