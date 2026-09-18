import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { MarkdownBody } from "./MarkdownBody";

describe("MarkdownBody", () => {
	it("renders GitHub-flavoured markdown with external links opening in a new window", () => {
		render(<MarkdownBody body={"| a | b |\n|---|---|\n| 1 | 2 |\n\n[docs](https://example.com)"} testId="md" />);
		const root = screen.getByTestId("md");
		expect(root.querySelector("table")).not.toBeNull();
		const link = screen.getByRole("link", { name: "docs" });
		expect(link).toHaveAttribute("target", "_blank");
		expect(link).toHaveAttribute("rel", "noopener noreferrer");
	});

	it("clamps when asked and merges extra classes", () => {
		render(<MarkdownBody body="text" clamped className="text-sm" testId="md" />);
		expect(screen.getByTestId("md")).toHaveClass("line-clamp-4", "text-sm");
	});
});
