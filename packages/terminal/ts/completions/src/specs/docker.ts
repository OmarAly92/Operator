import type { CommandSpec } from "../signature.js";

export const docker: CommandSpec = {
	name: "docker",
	alias: [],
	description: "Manage Docker containers, images, and networks",
	subcommands: [
		{
			name: "run",
			description: "Create and run a new container from an image",
			arguments: [
				{ name: "image", description: "Image to run" },
				{
					name: "command",
					description: "Command to run inside the container",
					optional: true,
					arity: {},
				},
			],
			options: [
				{ name: ["-it"], description: "Allocate a pseudo-TTY and keep STDIN open" },
				{ name: ["--rm"], description: "Automatically remove the container when it exits" },
				{ name: ["-p", "--publish"], description: "Publish a container's port(s) to the host", arguments: [{ name: "port" }] },
				{ name: ["-d", "--detach"], description: "Run the container in the background" },
				{ name: ["--name"], description: "Assign a name to the container", arguments: [{ name: "name" }] },
				{ name: ["-e", "--env"], description: "Set environment variables", arguments: [{ name: "env" }] },
				{ name: ["-v", "--volume"], description: "Bind mount a volume", arguments: [{ name: "volume" }] },
				{ name: ["--network"], description: "Connect the container to a network", arguments: [{ name: "network" }] },
				{ name: ["--restart"], description: "Restart policy to apply when the container exits", arguments: [{ name: "policy" }] },
				{ name: ["-u", "--user"], description: "Username or UID (format: <name|uid>[:<group|gid>])", arguments: [{ name: "user" }] },
			],
		},
		{
			name: "build",
			description: "Build an image from a Dockerfile",
			arguments: [
				{
					name: "path",
					description: "Build context directory",
					optional: true,
					values: [{ kind: "template", template: "folders" }],
				},
			],
			options: [
				{ name: ["-t", "--tag"], description: "Name and optionally a tag in the 'name:tag' format", arguments: [{ name: "tag" }] },
				{ name: ["-f", "--file"], description: "Name of the Dockerfile (default: 'PATH/Dockerfile')", arguments: [{ name: "dockerfile" }] },
				{ name: ["--build-arg"], description: "Set build-time variables", arguments: [{ name: "arg" }] },
				{ name: ["--no-cache"], description: "Do not use cache when building the image" },
				{ name: ["--pull"], description: "Always attempt to pull a newer version of the image" },
				{ name: ["-q", "--quiet"], description: "Suppress the build output and print image ID on success" },
				{ name: ["--target"], description: "Set the target build stage", arguments: [{ name: "stage" }] },
			],
		},
		{
			name: "ps",
			description: "List containers",
			options: [
				{ name: ["-a", "--all"], description: "Show all containers (default shows just running)" },
				{ name: ["-q", "--quiet"], description: "Only display container IDs" },
				{ name: ["--filter", "-f"], description: "Filter output based on conditions provided", arguments: [{ name: "filter" }] },
				{ name: ["--format"], description: "Pretty-print containers using a Go template", arguments: [{ name: "template" }] },
				{ name: ["-n", "--last"], description: "Show n last created containers (includes all states)", arguments: [{ name: "count" }] },
			],
		},
		{
			name: "images",
			description: "List images",
			options: [
				{ name: ["-a", "--all"], description: "Show all images (default hides intermediate images)" },
				{ name: ["-q", "--quiet"], description: "Only show image IDs" },
				{ name: ["--filter", "-f"], description: "Filter output based on conditions provided", arguments: [{ name: "filter" }] },
				{ name: ["--format"], description: "Pretty-print images using a Go template", arguments: [{ name: "template" }] },
				{ name: ["--digests"], description: "Show digests" },
			],
		},
		{
			name: "exec",
			description: "Execute a command in a running container",
			arguments: [
				{ name: "container", description: "Name or ID of the container" },
				{
					name: "command",
					description: "Command to execute",
					arity: {},
				},
			],
			options: [
				{ name: ["-it"], description: "Allocate a pseudo-TTY and keep STDIN open" },
				{ name: ["-d", "--detach"], description: "Run the command in the background" },
				{ name: ["-e", "--env"], description: "Set environment variables", arguments: [{ name: "env" }] },
				{ name: ["-u", "--user"], description: "Username or UID", arguments: [{ name: "user" }] },
				{ name: ["-w", "--workdir"], description: "Working directory inside the container", arguments: [{ name: "directory" }] },
			],
		},
		{
			name: "logs",
			description: "Fetch the logs of a container",
			arguments: [
				{ name: "container", description: "Name or ID of the container" },
			],
			options: [
				{ name: ["-f", "--follow"], description: "Follow log output" },
				{ name: ["--tail"], description: "Number of lines to show from the end of the logs", arguments: [{ name: "lines" }] },
				{ name: ["-t", "--timestamps"], description: "Show timestamps" },
				{ name: ["--since"], description: "Show logs since timestamp (e.g. 2013-01-02T13:23:37) or relative (e.g. 42m)", arguments: [{ name: "timestamp" }] },
				{ name: ["--until"], description: "Show logs before a timestamp", arguments: [{ name: "timestamp" }] },
			],
		},
		{
			name: "stop",
			description: "Stop one or more running containers",
			arguments: [
				{
					name: "container",
					description: "Name or ID of one or more containers",
					arity: {},
				},
			],
			options: [
				{ name: ["-t", "--time"], description: "Seconds to wait for stop before killing it", arguments: [{ name: "seconds" }] },
			],
		},
		{
			name: "start",
			description: "Start one or more stopped containers",
			arguments: [
				{
					name: "container",
					description: "Name or ID of one or more containers",
					arity: {},
				},
			],
		},
		{
			name: "rm",
			description: "Remove one or more containers",
			arguments: [
				{
					name: "container",
					description: "Name or ID of one or more containers",
					arity: {},
				},
			],
			options: [
				{ name: ["-f", "--force"], description: "Force the removal of a running container" },
				{ name: ["-v", "--volumes"], description: "Remove the volumes associated with the container" },
			],
		},
		{
			name: "rmi",
			description: "Remove one or more images",
			arguments: [
				{
					name: "image",
					description: "Name or ID of one or more images",
					arity: {},
				},
			],
			options: [
				{ name: ["-f", "--force"], description: "Force removal of the image" },
			],
		},
		{
			name: "pull",
			description: "Download an image from a registry",
			arguments: [
				{ name: "image", description: "Image to pull (e.g. nginx:latest)" },
			],
		},
		{
			name: "push",
			description: "Upload an image to a registry",
			arguments: [
				{ name: "image", description: "Image to push" },
			],
		},
		{
			name: "compose",
			description: "Define and run multi-container applications with Docker Compose",
			subcommands: [
				{
					name: "up",
					description: "Create and start containers",
					arguments: [
						{
							name: "path",
							description: "Project directory",
							optional: true,
							values: [{ kind: "template", template: "folders" }],
						},
					],
					options: [
						{ name: ["-d", "--detach"], description: "Detached mode: run containers in the background" },
						{ name: ["--build"], description: "Build images before starting containers" },
						{ name: ["-f", "--file"], description: "Compose configuration file", arguments: [{ name: "file" }] },
					],
				},
				{
					name: "down",
					description: "Stop and remove containers, networks, images, and volumes",
				},
				{
					name: "ps",
					description: "List containers",
				},
				{
					name: "logs",
					description: "View output from containers",
					arguments: [
						{ name: "service", description: "Service name", optional: true },
					],
				},
			],
		},
	],
};
