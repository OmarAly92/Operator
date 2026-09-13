import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

import { TunnelConfirmDialog } from "./TunnelConfirmDialog";
import { TUNNEL_CONFIRM_STORAGE_KEY } from "../../lib/tunnel-confirm";

describe("TunnelConfirmDialog", () => {
	beforeEach(() => {
		window.localStorage.clear();
	});

	test("states plainly what becomes reachable", () => {
		render(<TunnelConfirmDialog open onOpenChange={vi.fn()} onConfirm={vi.fn()} />);
		expect(screen.getByText("Make this desktop reachable from the internet?")).toBeTruthy();
		expect(screen.getByText(/start agents and run terminal commands/)).toBeTruthy();
	});

	test("confirming calls onConfirm and remembers the acknowledgement", async () => {
		const onConfirm = vi.fn();
		render(<TunnelConfirmDialog open onOpenChange={vi.fn()} onConfirm={onConfirm} />);

		await userEvent.click(screen.getByRole("button", { name: "Make it global" }));

		expect(onConfirm).toHaveBeenCalledTimes(1);
		expect(window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY)).toBe("1");
	});

	test("cancelling neither confirms nor remembers", async () => {
		const onConfirm = vi.fn();
		const onOpenChange = vi.fn();
		render(<TunnelConfirmDialog open onOpenChange={onOpenChange} onConfirm={onConfirm} />);

		await userEvent.click(screen.getByRole("button", { name: "Cancel" }));

		expect(onConfirm).not.toHaveBeenCalled();
		expect(window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY)).toBeNull();
		expect(onOpenChange).toHaveBeenCalledWith(false);
	});
});
