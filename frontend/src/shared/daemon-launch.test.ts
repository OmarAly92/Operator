import { describe, expect, it } from "vitest";
import { resolveDaemonLaunch } from "./daemon-launch";

describe("resolveDaemonLaunch", () => {
	it("uses OPERATOR_DAEMON_COMMAND when configured", () => {
		expect(
			resolveDaemonLaunch({ OPERATOR_DAEMON_COMMAND: "/tmp/opr daemon" }, false, "/resources", "/app", "/home/user", "darwin"),
		).toEqual({
			command: "/tmp/opr daemon",
			args: [],
			cwd: "/app",
			shell: true,
			source: "configured",
		});
	});

	it("runs the backend daemon from source in dev without an explicit command", () => {
		expect(resolveDaemonLaunch({}, false, "/resources", "/repo/frontend", "/home/user", "darwin")).toEqual({
			command: "go",
			args: ["run", "./cmd/opr", "daemon"],
			cwd: "/repo/frontend/../backend",
			shell: false,
			source: "dev",
		});
	});

	it("uses the bundled daemon binary for packaged macOS/Linux builds", () => {
		expect(
			resolveDaemonLaunch(
				{},
				true,
				"/Applications/Operator.app/Contents/Resources",
				"/app",
				"/Users/alice",
				"darwin",
			),
		).toEqual({
			command: "/Applications/Operator.app/Contents/Resources/daemon/opr",
			args: ["daemon"],
			cwd: "/Users/alice/.operator",
			shell: false,
			source: "bundled",
		});
	});

	it("uses the bundled daemon exe for packaged Windows builds", () => {
		expect(
			resolveDaemonLaunch(
				{},
				true,
				"C:\\Program Files\\Operator\\resources",
				"C:\\Program Files\\Operator\\resources\\app.asar",
				"C:\\Users\\alice",
				"win32",
			),
		).toEqual({
			command: "C:\\Program Files\\Operator\\resources/daemon/opr.exe",
			args: ["daemon"],
			cwd: "C:\\Users\\alice/.operator",
			shell: false,
			source: "bundled",
		});
	});
});
