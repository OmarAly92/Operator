import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
	permission: vi.fn(),
	openSettings: vi.fn(),
	show: vi.fn(),
	status: undefined as unknown,
	sendTest: vi.fn(),
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { notifications: { permission: h.permission, openSettings: h.openSettings, show: h.show } },
}));

vi.mock("../../hooks/usePhoneAlerts", () => ({
	usePhoneAlerts: () => ({ data: h.status }),
	useTestPhoneAlert: () => ({ mutate: h.sendTest, isPending: false }),
}));

import { NotificationsSection } from "./NotificationsSection";

beforeEach(() => {
	for (const fn of [h.permission, h.openSettings, h.show, h.sendTest]) fn.mockReset();
	h.permission.mockResolvedValue("authorized");
	h.status = { enabled: true, claimed: true };
});

test("denied permission offers System Settings", async () => {
	h.permission.mockResolvedValue("denied");
	render(<NotificationsSection />);
	expect(await screen.findByText("Off in System Settings")).toBeTruthy();
	await userEvent.click(screen.getByRole("button", { name: "Open System Settings" }));
	expect(h.openSettings).toHaveBeenCalledTimes(1);
});

test("the Mac test posts a test notification", async () => {
	render(<NotificationsSection />);
	await userEvent.click(screen.getAllByRole("button", { name: "Send test" })[0]);
	expect(h.show).toHaveBeenCalledWith(expect.objectContaining({ type: "test", title: "Operator" }));
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
