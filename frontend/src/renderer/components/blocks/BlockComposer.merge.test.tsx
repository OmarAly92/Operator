import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { BlockComposer, type BlockComposerSend } from "./BlockComposer";

function renderComposer(props: Partial<Parameters<typeof BlockComposer>[0]> & { sessionId: string }) {
	return render(
		<BlockComposer {...props} send={props.send ?? vi.fn().mockResolvedValue(undefined)} />,
	);
}

describe("BlockComposer merge", () => {
	let sendMock: BlockComposerSend;
	beforeEach(() => {
		sendMock = vi.fn().mockResolvedValue(undefined);
	});

	it("does not show the attach affordance when no onAttach prop is passed (tui path)", () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		expect(screen.queryByTestId("block-attach")).not.toBeInTheDocument();
		expect(screen.getByTestId("block-send")).toBeInTheDocument();
	});

	it("shows the attach button when onAttach is passed (chat path)", () => {
		renderComposer({
			sessionId: "s-1",
			send: sendMock,
			onAttach: vi.fn(),
		});

		expect(screen.getByTestId("block-attach")).toBeInTheDocument();
	});

	it("hides the attach button when onAttach is not passed", () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		expect(screen.queryByTestId("block-attach")).not.toBeInTheDocument();
	});

	it("calls onAttach with the selected files", async () => {
		const onAttach = vi.fn();
		renderComposer({
			sessionId: "s-1",
			send: sendMock,
			onAttach,
		});

		const file = new File(["hello"], "greeting.txt", { type: "text/plain" });
		const input = document.querySelector('input[type="file"]') as HTMLInputElement;
		expect(input).toBeTruthy();
		await userEvent.upload(input, file);

		await waitFor(() => expect(onAttach).toHaveBeenCalledTimes(1));
		expect(onAttach.mock.calls[0]![0]).toHaveLength(1);
		expect(onAttach.mock.calls[0]![0][0]!.name).toBe("greeting.txt");
	});

	it("routes the send through onSteer when canSteer and onSteer are present", async () => {
		const onSteer = vi.fn().mockResolvedValue(undefined);
		renderComposer({
			sessionId: "s-1",
			send: sendMock,
			onSteer,
			canSteer: true,
		});

		const field = screen.getByLabelText("Message the agent");
		await userEvent.type(field, "redirect now");
		await userEvent.click(screen.getByTestId("block-send"));

		await waitFor(() => expect(onSteer).toHaveBeenCalledWith("redirect now"));
		expect(sendMock).not.toHaveBeenCalled();
	});

	it("routes the send through the send function when steer is not available", async () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		await userEvent.type(screen.getByLabelText("Message the agent"), "run it");
		await userEvent.click(screen.getByTestId("block-send"));

		await waitFor(() => expect(sendMock).toHaveBeenCalledWith({ text: "run it" }));
	});

	it("shows the slash-suggest menu when suggestions are provided", () => {
		renderComposer({
			sessionId: "s-1",
			send: sendMock,
			suggestions: {
				trigger: "/",
				query: "",
				items: [
					{ value: "review", label: "review" },
					{ value: "refactor", label: "refactor" },
				],
			},
		});

		expect(screen.getByRole("listbox")).toBeInTheDocument();
		expect(screen.getByText("/review")).toBeInTheDocument();
		expect(screen.getByText("/refactor")).toBeInTheDocument();
	});

	it("does not show the slash-suggest menu when no suggestions are provided", () => {
		renderComposer({ sessionId: "s-1", send: sendMock });

		expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
	});
});
