import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it } from "vitest";
import { BlockFindBar } from "./BlockFindBar";

function Harness() {
	const [open, setOpen] = useState(true);
	const [query, setQuery] = useState("");
	const [activeIndex, setActiveIndex] = useState(0);
	const [filtering, setFiltering] = useState(false);
	if (!open) return null;
	return (
		<BlockFindBar
			activeIndex={activeIndex}
			filtering={filtering}
			matchCount={3}
			onClose={() => setOpen(false)}
			onNext={() => setActiveIndex((index) => (index + 1) % 3)}
			onPrevious={() => setActiveIndex((index) => (index + 2) % 3)}
			onQueryChange={setQuery}
			onToggleFilter={() => setFiltering((current) => !current)}
			query={query}
		/>
	);
}

describe("BlockFindBar", () => {
	it("lets a user type, navigate with Enter, toggle filtering, and close with Escape", async () => {
		const user = userEvent.setup();
		render(<Harness />);

		const input = screen.getByRole("textbox", { name: "Find in blocks" });
		await user.type(input, "deploy");
		expect(input).toHaveValue("deploy");
		expect(screen.getByText("1 / 3")).toBeInTheDocument();

		await user.keyboard("{Enter}");
		expect(screen.getByText("2 / 3")).toBeInTheDocument();
		await user.keyboard("{Shift>}{Enter}{/Shift}");
		expect(screen.getByText("1 / 3")).toBeInTheDocument();
		await user.click(screen.getByRole("button", { name: "Filter results" }));
		expect(screen.getByRole("button", { name: "Filter results" })).toHaveAttribute("aria-pressed", "true");

		await user.keyboard("{Escape}");
		expect(screen.queryByRole("textbox", { name: "Find in blocks" })).not.toBeInTheDocument();
	});
});
