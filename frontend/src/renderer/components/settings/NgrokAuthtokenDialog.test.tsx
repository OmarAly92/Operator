import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { post } = vi.hoisted(() => ({ post: vi.fn() }));
const { openExternal } = vi.hoisted(() => ({ openExternal: vi.fn() }));

vi.mock("../../lib/api-client", () => ({
	apiClient: { POST: post },
	apiErrorMessage: (error: unknown) => String((error as { message?: string })?.message ?? "failed"),
}));

vi.mock("../../lib/bridge", () => ({
	operatorBridge: { app: { openExternal } },
}));

import { NgrokAuthtokenDialog } from "./NgrokAuthtokenDialog";

function renderDialog(props: {
	open?: boolean;
	onOpenChange?: (open: boolean) => void;
	onSaved?: () => void;
}) {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<NgrokAuthtokenDialog
				open={props.open ?? true}
				onOpenChange={props.onOpenChange ?? vi.fn()}
				onSaved={props.onSaved ?? vi.fn()}
			/>
		</QueryClientProvider>,
	);
}

describe("NgrokAuthtokenDialog", () => {
	beforeEach(() => {
		post.mockReset();
		post.mockResolvedValue({ data: {}, error: undefined });
		openExternal.mockReset();
	});

	test("explains the benefit and offers the token page", () => {
		renderDialog({});
		expect(screen.getByText("Pair once with ngrok")).toBeTruthy();
		expect(screen.getByRole("button", { name: "Get my authtoken" })).toBeTruthy();
	});

	test("masks the field by default", () => {
		renderDialog({});
		const field = screen.getByLabelText("ngrok authtoken", { selector: "input" });
		expect(field.getAttribute("type")).toBe("password");
	});

	test("the token page opens in the default browser, not embedded", async () => {
		renderDialog({});
		await userEvent.click(screen.getByRole("button", { name: "Get my authtoken" }));
		expect(openExternal).toHaveBeenCalledWith("https://dashboard.ngrok.com/get-started/your-authtoken");
	});

	test("saving posts the token and reports success", async () => {
		const onSaved = vi.fn();
		renderDialog({ onSaved });

		await userEvent.type(screen.getByLabelText("ngrok authtoken", { selector: "input" }), "2abc_secret");
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));

		await waitFor(() =>
			expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/authtoken", {
				body: { token: "2abc_secret" },
			}),
		);
		await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1));
	});

	test("a rejected token shows the provider's message and stays open", async () => {
		post.mockResolvedValue({ data: undefined, error: { message: "ngrok rejected the authtoken: invalid" } });
		const onSaved = vi.fn();
		renderDialog({ onSaved });

		await userEvent.type(screen.getByLabelText("ngrok authtoken", { selector: "input" }), "bogus");
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));

		await waitFor(() => expect(screen.getByText(/invalid/)).toBeTruthy());
		expect(onSaved).not.toHaveBeenCalled();
	});

	test("an empty field cannot be submitted", async () => {
		renderDialog({});
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));
		expect(post).not.toHaveBeenCalled();
	});

	test("dismissing changes nothing", async () => {
		const onOpenChange = vi.fn();
		renderDialog({ onOpenChange });

		await userEvent.click(screen.getByRole("button", { name: "Not now" }));

		expect(post).not.toHaveBeenCalled();
		expect(onOpenChange).toHaveBeenCalledWith(false);
	});
});
