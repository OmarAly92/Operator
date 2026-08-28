import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiClient } from "../../lib/api-client";
import { BlockComposer } from "./BlockComposer";

const postMock = vi.spyOn(apiClient, "POST");

describe("BlockComposer", () => {
	beforeEach(() => {
		postMock.mockReset();
		postMock.mockResolvedValue({ data: { ok: true, sessionId: "s-1", message: "sent" } } as never);
	});

	it("sends the draft to the session send route", async () => {
		render(<BlockComposer sessionId="s-1" />);

		await userEvent.type(screen.getByLabelText("Message the agent"), "run the tests");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(postMock).toHaveBeenCalledTimes(1));
		expect(postMock).toHaveBeenCalledWith("/api/v1/sessions/{sessionId}/send", {
			params: { path: { sessionId: "s-1" } },
			body: { message: "run the tests" },
		});
	});

	it("clears the draft once the message is accepted", async () => {
		render(<BlockComposer sessionId="s-1" />);
		const field = screen.getByLabelText("Message the agent");

		await userEvent.type(field, "hello");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(field).toHaveValue(""));
	});

	it("submits on Enter without a separate click", async () => {
		render(<BlockComposer sessionId="s-1" />);

		await userEvent.type(screen.getByLabelText("Message the agent"), "hi{Enter}");

		await waitFor(() => expect(postMock).toHaveBeenCalledTimes(1));
	});

	it("refuses to send an empty or whitespace-only draft", async () => {
		render(<BlockComposer sessionId="s-1" />);

		expect(screen.getByRole("button", { name: "Send" })).toBeDisabled();
		await userEvent.type(screen.getByLabelText("Message the agent"), "   ");
		expect(screen.getByRole("button", { name: "Send" })).toBeDisabled();
		expect(postMock).not.toHaveBeenCalled();
	});

	it("keeps the draft and surfaces the failure when the send is rejected", async () => {
		postMock.mockResolvedValue({ error: { message: "agent is not running" } } as never);
		render(<BlockComposer sessionId="s-1" />);
		const field = screen.getByLabelText("Message the agent");

		await userEvent.type(field, "retry me");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(screen.getByText(/agent is not running/)).toBeInTheDocument());
		expect(field).toHaveValue("retry me");
	});
});
