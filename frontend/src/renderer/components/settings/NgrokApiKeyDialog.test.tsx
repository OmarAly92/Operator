import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { openExternal } = vi.hoisted(() => ({ openExternal: vi.fn() }));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { app: { openExternal } },
}));

import { NgrokApiKeyDialog } from "./NgrokApiKeyDialog";

function renderDialog(props: {
	open?: boolean;
	onOpenChange?: (open: boolean) => void;
	onSave?: (key: string) => Promise<unknown>;
}) {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<NgrokApiKeyDialog
				open={props.open ?? true}
				onOpenChange={props.onOpenChange ?? vi.fn()}
				onSave={props.onSave ?? vi.fn(async () => ({}))}
			/>
		</QueryClientProvider>,
	);
}

describe("NgrokApiKeyDialog", () => {
	beforeEach(() => {
		openExternal.mockReset();
	});

	test("typing a key and pressing Save calls onSave, clears the input and closes", async () => {
		const onSave = vi.fn(async () => ({}));
		const onOpenChange = vi.fn();
		renderDialog({ onSave, onOpenChange });

		const input = screen.getByLabelText("ngrok API key") as HTMLInputElement;
		await userEvent.type(input, "k");
		await userEvent.click(screen.getByRole("button", { name: "Save" }));

		await waitFor(() => expect(onSave).toHaveBeenCalledWith("k"));
		await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
		expect(input.value).toBe("");
	});

	test("a rejected onSave shows the error text and keeps the dialog open", async () => {
		const onSave = vi.fn(async () => {
			throw new Error("tunnel: ngrok rejected the API key");
		});
		const onOpenChange = vi.fn();
		renderDialog({ onSave, onOpenChange });

		await userEvent.type(screen.getByLabelText("ngrok API key"), "bogus");
		await userEvent.click(screen.getByRole("button", { name: "Save" }));

		await waitFor(() => expect(screen.getByText(/rejected the API key/)).toBeInTheDocument());
		expect(onOpenChange).not.toHaveBeenCalledWith(false);
	});

	test("the dashboard button opens the ngrok API keys page", async () => {
		renderDialog({});
		await userEvent.click(screen.getByRole("button", { name: "Get an API key" }));
		expect(openExternal).toHaveBeenCalledWith("https://dashboard.ngrok.com/api-keys");
	});
});
