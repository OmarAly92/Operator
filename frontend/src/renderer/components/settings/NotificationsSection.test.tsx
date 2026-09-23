import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
	permission: vi.fn(),
	openSettings: vi.fn(),
	show: vi.fn(),
	status: undefined as unknown,
	phoneLoading: false,
	phoneError: false,
	sendTest: vi.fn(),
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { notifications: { permission: h.permission, openSettings: h.openSettings, show: h.show } },
}));

vi.mock("../../hooks/usePhoneAlerts", () => ({
	usePhoneAlerts: () => ({ data: h.status, isLoading: h.phoneLoading, isError: h.phoneError }),
	useTestPhoneAlert: () => ({ mutate: h.sendTest, isPending: false }),
}));

import { NotificationsSection } from "./NotificationsSection";

beforeEach(() => {
	for (const fn of [h.permission, h.openSettings, h.show, h.sendTest]) fn.mockReset();
	h.permission.mockResolvedValue("authorized");
	h.show.mockResolvedValue(undefined);
	h.status = { enabled: true, claimed: true };
	h.phoneLoading = false;
	h.phoneError = false;
	vi.spyOn(console, "warn").mockImplementation(() => undefined);
});

test("denied permission offers System Settings", async () => {
	h.permission.mockResolvedValue("denied");
	render(<NotificationsSection />);
	expect(await screen.findByText("Off in System Settings")).toBeTruthy();
	await userEvent.click(screen.getByRole("button", { name: "Open System Settings" }));
	expect(h.openSettings).toHaveBeenCalledTimes(1);
});

test("shows a loading state before the permission call resolves, never the unsupported flash", async () => {
	h.permission.mockImplementation(() => new Promise(() => undefined));
	render(<NotificationsSection />);
	expect(screen.getByText("Checking…")).toBeTruthy();
	expect(screen.queryByText("Not available in this build")).not.toBeInTheDocument();
});

test("falls back to unsupported and logs when the permission call rejects", async () => {
	h.permission.mockRejectedValue(new Error("bridge unavailable"));
	render(<NotificationsSection />);
	expect(await screen.findByText("Not available in this build")).toBeTruthy();
	expect(console.warn).toHaveBeenCalledWith(
		"Unable to read the macOS notification permission",
		expect.any(Error),
	);
});

test("the Mac test posts a test notification", async () => {
	render(<NotificationsSection />);
	await userEvent.click(screen.getAllByRole("button", { name: "Send test" })[0]);
	expect(h.show).toHaveBeenCalledWith(expect.objectContaining({ type: "test", title: "Operator" }));
});

test("a denied Mac test flips permission to denied and offers System Settings", async () => {
	h.show.mockRejectedValue(new Error("notification_permission=denied: not authorized"));
	render(<NotificationsSection />);
	await userEvent.click(screen.getAllByRole("button", { name: "Send test" })[0]);
	expect(await screen.findByText("Off in System Settings")).toBeTruthy();
	expect(await screen.findByRole("button", { name: "Open System Settings" })).toBeTruthy();
});

test("a non-permission Mac test failure shows an inline error next to Send test", async () => {
	h.show.mockRejectedValue(new Error("The native bridge is unavailable"));
	render(<NotificationsSection />);
	await userEvent.click(screen.getAllByRole("button", { name: "Send test" })[0]);
	expect(await screen.findByText("The native bridge is unavailable")).toBeTruthy();
	expect(screen.queryByText("Off in System Settings")).not.toBeInTheDocument();
});

test("renders nothing for the phone line while the phone-alerts query is loading", async () => {
	h.phoneLoading = true;
	h.status = undefined;
	render(<NotificationsSection />);
	await screen.findByText("Allowed");
	expect(screen.queryByText("Off — Connect Mobile is off")).not.toBeInTheDocument();
	expect(screen.queryByText("On for your paired phone")).not.toBeInTheDocument();
});

test("shows an error line when the phone-alerts query fails", async () => {
	h.phoneError = true;
	h.status = undefined;
	render(<NotificationsSection />);
	expect(await screen.findByText("Could not load phone status.")).toBeTruthy();
});

test.each([
	[{ enabled: false, claimed: false }, "Off — Connect Mobile is off", true],
	[{ enabled: true, claimed: false }, "Waiting for the phone to subscribe", true],
	[
		{ enabled: true, claimed: true, lastDelivery: { at: "2026-09-23T10:00:00Z", ok: false, error: "ntfy answered 429" } },
		"Last attempt failed: ntfy answered 429",
		false,
	],
	[{ enabled: true, claimed: true }, "On for your paired phone", false],
])("phone status %o reads %s", async (status, line, disabled) => {
	h.status = status;
	render(<NotificationsSection />);
	expect(await screen.findByText(line)).toBeTruthy();
	const phoneButton = screen.getAllByRole("button", { name: "Send test" })[1] as HTMLButtonElement;
	await waitFor(() => expect(phoneButton.disabled).toBe(disabled));
});

test("a successful delivery shows a relative time", async () => {
	h.status = {
		enabled: true,
		claimed: true,
		lastDelivery: { at: new Date(Date.now() - 2 * 60_000).toISOString(), ok: true },
	};
	render(<NotificationsSection />);
	expect(await screen.findByText("On for your paired phone · last delivered 2m ago")).toBeTruthy();
});
