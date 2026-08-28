import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { BlockComposer, type BlockComposerSend } from "./BlockComposer";

describe("BlockComposer", () => {
	let sendMock: BlockComposerSend;

	beforeEach(() => {
		sendMock = vi.fn().mockResolvedValue(undefined);
	});

	function renderComposer(props: { sessionId: string; send: BlockComposerSend }) {
		return render(<BlockComposer {...props} />);
	}

	it("sends the draft to the provided send function", async () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		await userEvent.type(screen.getByLabelText("Message the agent"), "run the tests");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(sendMock).toHaveBeenCalledTimes(1));
		expect(sendMock).toHaveBeenCalledWith({ text: "run the tests" });
	});

	it("clears the draft once the message is accepted", async () => {
		renderComposer({ sessionId: "s-1", send: sendMock });
		const field = screen.getByLabelText("Message the agent");

		await userEvent.type(field, "hello");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(field).toHaveValue(""));
	});

	it("submits on Enter without a separate click", async () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		await userEvent.type(screen.getByLabelText("Message the agent"), "hi{Enter}");

		await waitFor(() => expect(sendMock).toHaveBeenCalledTimes(1));
	});

	it("refuses to send an empty or whitespace-only draft", async () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		expect(screen.getByRole("button", { name: "Send" })).toBeDisabled();
		await userEvent.type(screen.getByLabelText("Message the agent"), "   ");
		expect(screen.getByRole("button", { name: "Send" })).toBeDisabled();
		expect(sendMock).not.toHaveBeenCalled();
	});

	it("keeps the draft and surfaces the failure when the send is rejected", async () => {
		sendMock = vi.fn().mockRejectedValueOnce(new Error("agent is not running"));
		renderComposer({ sessionId: "s-1", send: sendMock });
		const field = screen.getByLabelText("Message the agent");

		await userEvent.type(field, "retry me");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(screen.getByText(/agent is not running/)).toBeInTheDocument());
		expect(field).toHaveValue("retry me");
	});

	it("routes the trimmed text through the chat send function", async () => {
		const chatSend: BlockComposerSend = vi.fn().mockResolvedValue(undefined);
		renderComposer({ sessionId: "s-1", send: chatSend });

		await userEvent.type(screen.getByLabelText("Message the agent"), "   ping the agent   ");
		await userEvent.click(screen.getByRole("button", { name: "Send" }));

		await waitFor(() => expect(chatSend).toHaveBeenCalledWith({ text: "ping the agent" }));
	});
});
