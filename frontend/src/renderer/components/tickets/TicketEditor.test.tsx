import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ComponentProps } from "react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { TicketFile } from "../../hooks/useTicketsQuery";
import { TooltipProvider } from "../ui/tooltip";

const { saveMock } = vi.hoisted(() => ({ saveMock: vi.fn() }));

vi.mock("../../hooks/useTicketMutations", async (importOriginal) => {
	const actual = await importOriginal<typeof import("../../hooks/useTicketMutations")>();
	return { ...actual, useTicketMutations: () => ({ saveTicketFile: { mutateAsync: saveMock, isPending: false } }) };
});

vi.mock("./CodeMirrorField", () => ({
	CodeMirrorField: ({
		value,
		onChange,
		onSave,
		onTopLineChange,
		ariaLabel,
	}: {
		value: string;
		onChange: (next: string) => void;
		onSave: () => void;
		onTopLineChange?: (line: number) => void;
		ariaLabel: string;
	}) => (
		<div>
			<textarea
				aria-label={ariaLabel}
				value={value}
				onChange={(event) => onChange(event.target.value)}
				onKeyDown={(event) => {
					if (event.key === "s" && (event.metaKey || event.ctrlKey)) {
						event.preventDefault();
						onSave();
					}
				}}
			/>
			<button type="button" onClick={() => onTopLineChange?.(9)}>
				scroll to line 9
			</button>
		</div>
	),
}));

import { TicketEditor } from "./TicketEditor";

const body = ["# Spec", "", "Intro.", "", "## Goals", "", "Goal text.", "", "### Details", "more"].join("\n");
const file: TicketFile = { path: "spec.md", content: body, modifiedAt: "2026-09-18T10:00:00Z" };

function renderEditor(current: TicketFile | undefined = file, props: Partial<ComponentProps<typeof TicketEditor>> = {}) {
	const reload = vi.fn().mockResolvedValue(undefined);
	const view = render(
		<QueryClientProvider client={new QueryClient()}>
			<TooltipProvider>
				<TicketEditor projectId="p1" slug="search-page" path="spec.md" file={current} isError={false} reload={reload} {...props} />
			</TooltipProvider>
		</QueryClientProvider>,
	);
	const rerenderWith = (next: TicketFile) =>
		view.rerender(
			<QueryClientProvider client={new QueryClient()}>
				<TooltipProvider>
					<TicketEditor projectId="p1" slug="search-page" path="spec.md" file={next} isError={false} reload={reload} {...props} />
				</TooltipProvider>
			</QueryClientProvider>,
		);
	return { reload, rerenderWith, unmount: view.unmount };
}

async function switchTo(mode: "Edit" | "Preview" | "Split") {
	await userEvent.click(within(screen.getByRole("radiogroup", { name: "View" })).getByRole("radio", { name: mode }));
}

beforeAll(() => {
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

beforeEach(() => {
	saveMock.mockReset();
});

describe("TicketEditor", () => {
	it("previews by default, has no Save button and shows the pending dot while typing", async () => {
		saveMock.mockReturnValue(new Promise(() => undefined));
		renderEditor();
		expect(screen.getByTestId("ticket-file-preview")).toHaveTextContent("Intro.");
		expect(screen.queryByRole("button", { name: "Save" })).not.toBeInTheDocument();
		expect(screen.queryByRole("status", { name: "Unsaved changes" })).not.toBeInTheDocument();

		await switchTo("Edit");
		const editor = screen.getByLabelText("Edit spec.md");
		expect(editor).toHaveValue(body);
		await userEvent.type(editor, "!");

		expect(screen.getByRole("status", { name: "Unsaved changes" })).toBeInTheDocument();
	});

	it("auto-saves the draft with ifUnmodifiedSince shortly after typing stops", async () => {
		saveMock.mockResolvedValue({ ...file, content: `${body}!!`, modifiedAt: "2026-09-18T10:05:00Z" });
		renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!!");
		expect(saveMock).not.toHaveBeenCalled();

		await waitFor(() =>
			expect(saveMock).toHaveBeenCalledWith({
				projectId: "p1",
				slug: "search-page",
				path: "spec.md",
				content: `${body}!!`,
				ifUnmodifiedSince: "2026-09-18T10:00:00Z",
			}),
		);
		expect(saveMock).toHaveBeenCalledTimes(1);
		expect(await screen.findByText("Saved")).toBeInTheDocument();
		expect(screen.queryByRole("status", { name: "Unsaved changes" })).not.toBeInTheDocument();
	});

	it("saves immediately on Cmd+S", async () => {
		saveMock.mockResolvedValue({ ...file, content: `${body}!`, modifiedAt: "2026-09-18T10:05:00Z" });
		renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		await userEvent.keyboard("{Meta>}s{/Meta}");

		expect(saveMock).toHaveBeenCalledTimes(1);
		expect(saveMock.mock.calls[0][0]).toMatchObject({ content: `${body}!` });
		expect(await screen.findByText("Saved")).toBeInTheDocument();
	});

	it("flushes a pending draft when unmounted", async () => {
		saveMock.mockResolvedValue({ ...file, content: `${body}!`, modifiedAt: "2026-09-18T10:05:00Z" });
		const { unmount } = renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		expect(saveMock).not.toHaveBeenCalled();

		unmount();

		expect(saveMock).toHaveBeenCalledTimes(1);
		expect(saveMock.mock.calls[0][0]).toMatchObject({ content: `${body}!` });
	});

	it("shows the stale bar on 409 and Keep mine saves without ifUnmodifiedSince", async () => {
		saveMock
			.mockRejectedValueOnce({ error: "conflict", code: "TICKET_FILE_STALE", message: "stale", details: { modifiedAt: "2026-09-18T10:03:00Z" } })
			.mockResolvedValueOnce({ ...file, content: `${body}!`, modifiedAt: "2026-09-18T10:06:00Z" });
		renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");

		const bar = await screen.findByTestId("ticket-file-stale");
		expect(bar).toHaveTextContent("This file changed on disk");
		await userEvent.click(within(bar).getByRole("button", { name: "Keep mine" }));

		await waitFor(() => expect(saveMock).toHaveBeenCalledTimes(2));
		expect(saveMock.mock.calls[1][0]).toMatchObject({ content: `${body}!`, ifUnmodifiedSince: undefined });
		await waitFor(() => expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument());
	});

	it("Reload drops the draft and refetches", async () => {
		saveMock.mockRejectedValue({ error: "conflict", code: "TICKET_FILE_STALE", message: "stale", details: { modifiedAt: "2026-09-18T10:03:00Z" } });
		const { reload } = renderEditor();
		await switchTo("Edit");
		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		const bar = await screen.findByTestId("ticket-file-stale");
		expect(saveMock).toHaveBeenCalledTimes(1);

		await userEvent.click(within(bar).getByRole("button", { name: "Reload" }));

		expect(reload).toHaveBeenCalled();
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(body);
		expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument();
	});

	it("adopts a changed file silently when clean and shows the bar when dirty", async () => {
		const { rerenderWith } = renderEditor();
		await switchTo("Edit");
		rerenderWith({ ...file, content: `${body}\n\nFrom disk.`, modifiedAt: "2026-09-18T10:01:00Z" });
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(`${body}\n\nFrom disk.`);
		expect(screen.queryByTestId("ticket-file-stale")).not.toBeInTheDocument();

		await userEvent.type(screen.getByLabelText("Edit spec.md"), "!");
		rerenderWith({ ...file, content: `${body}\n\nSecond write.`, modifiedAt: "2026-09-18T10:02:00Z" });

		expect(await screen.findByTestId("ticket-file-stale")).toBeInTheDocument();
		expect(screen.getByLabelText("Edit spec.md")).toHaveValue(`${body}\n\nFrom disk.!`);
		await new Promise((resolve) => setTimeout(resolve, 700));
		expect(saveMock).not.toHaveBeenCalled();
	});

	it("scrolls the split preview to the heading nearest the editor's top line", async () => {
		renderEditor();
		await switchTo("Split");
		const preview = screen.getByTestId("ticket-file-preview");
		const details = within(preview).getByRole("heading", { name: "Details" });
		const spy = vi.spyOn(details, "scrollIntoView");

		await userEvent.click(screen.getByRole("button", { name: "scroll to line 9" }));
		await act(async () => {
			await new Promise((resolve) => requestAnimationFrame(() => resolve(undefined)));
		});

		expect(spy).toHaveBeenCalledWith({ block: "start" });
	});
});
