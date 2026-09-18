import { EditorView } from "@codemirror/view";
import { act, fireEvent, render, screen } from "@testing-library/react";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { CodeMirrorField } from "./CodeMirrorField";

beforeAll(() => {
	const emptyRect = { x: 0, y: 0, width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0, toJSON: () => ({}) } as DOMRect;
	Range.prototype.getBoundingClientRect = () => emptyRect;
	Range.prototype.getClientRects = () =>
		({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
	if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => undefined;
});

function viewOf(testId = "codemirror-field"): EditorView {
	const view = EditorView.findFromDOM(screen.getByTestId(testId) as HTMLElement);
	if (!view) throw new Error("no editor view mounted");
	return view;
}

describe("CodeMirrorField", () => {
	it("mounts a labelled markdown editor with the initial value", () => {
		render(<CodeMirrorField value="# Hello" onChange={vi.fn()} onSave={vi.fn()} ariaLabel="Edit spec.md" />);
		expect(screen.getByLabelText("Edit spec.md")).toHaveClass("cm-content");
		expect(viewOf().state.doc.toString()).toBe("# Hello");
	});

	it("reports edits and adopts external value changes without echoing them", () => {
		const onChange = vi.fn();
		const { rerender } = render(<CodeMirrorField value="one" onChange={onChange} onSave={vi.fn()} ariaLabel="Edit" />);
		act(() => {
			viewOf().dispatch({ changes: { from: 3, insert: " two" } });
		});
		expect(onChange).toHaveBeenCalledWith("one two");

		rerender(<CodeMirrorField value="three" onChange={onChange} onSave={vi.fn()} ariaLabel="Edit" />);
		expect(viewOf().state.doc.toString()).toBe("three");
		expect(onChange).toHaveBeenCalledTimes(1);
	});

	it("runs onSave for Mod-s and swallows the browser default", () => {
		const onSave = vi.fn();
		render(<CodeMirrorField value="x" onChange={vi.fn()} onSave={onSave} ariaLabel="Edit" />);
		const content = screen.getByLabelText("Edit");
		const prevented = !fireEvent.keyDown(content, { key: "s", code: "KeyS", ctrlKey: true });
		expect(onSave).toHaveBeenCalledTimes(1);
		expect(prevented).toBe(true);
	});
});
