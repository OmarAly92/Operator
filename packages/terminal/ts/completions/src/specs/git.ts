import type { CommandSpec } from "../signature.js";

export const git: CommandSpec = {
	name: "git",
	alias: [],
	description: "Distributed version control system",
	subcommands: [
		{
			name: "add",
			description: "Add file contents to the index",
			arguments: [
				{
					name: "pathspec",
					description: "Files and folders to add",
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
			options: [
				{ name: ["-A", "--all"], description: "Add changes from all tracked and untracked files" },
				{ name: ["-u", "--update"], description: "Update the index just where it already matches" },
				{ name: ["-n", "--dry-run"], description: "Don't actually add the files, just show whether they exist" },
				{ name: ["-v", "--verbose"], description: "Be verbose" },
				{ name: ["-f", "--force"], description: "Allow adding otherwise ignored files" },
			],
		},
		{
			name: "commit",
			description: "Record changes to the repository",
			arguments: [
				{
					name: "pathspec",
					description: "Files and folders to commit",
					optional: true,
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
			options: [
				{ name: ["-m", "--message"], description: "Use the given message as the commit message", arguments: [{ name: "message" }] },
				{ name: ["-a", "--all"], description: "Stage all modified and deleted files" },
				{ name: ["--amend"], description: "Amend the previous commit instead of creating a new one" },
				{ name: ["-e", "--edit"], description: "Force the editor to start with the existing message" },
				{ name: ["--no-edit"], description: "Use the selected commit message without launching an editor" },
				{ name: ["--allow-empty"], description: "Allow recording an empty commit" },
				{ name: ["-v", "--verbose"], description: "Show the diff being committed" },
				{ name: ["-q", "--quiet"], description: "Suppress commit summary message" },
			],
		},
		{
			name: "checkout",
			alias: ["co"],
			description: "Switch branches or restore working tree files",
			priority: 60,
			arguments: [
				{
					name: "branch",
					description: "Branch, tag, or commit to check out",
					optional: true,
				},
				{
					name: "pathspec",
					description: "Files and folders to restore",
					optional: true,
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
			options: [
				{ name: ["-b"], description: "Create a new branch and check it out", arguments: [{ name: "branch" }] },
				{ name: ["-B"], description: "Create or reset a branch and check it out", arguments: [{ name: "branch" }] },
				{ name: ["-f", "--force"], description: "Force the checkout" },
				{ name: ["-q", "--quiet"], description: "Suppress feedback messages" },
				{ name: ["--"], description: "Separate the branch from the paths" },
			],
		},
		{
			name: "push",
			description: "Update remote refs along with associated objects",
			arguments: [
				{
					name: "remote",
					description: "Remote to push to",
					optional: true,
				},
				{
					name: "refspec",
					description: "What to push",
					arity: {},
					optional: true,
				},
			],
			options: [
				{ name: ["-u", "--set-upstream"], description: "Set upstream for the branch being pushed" },
				{ name: ["-f", "--force"], description: "Force the push" },
				{ name: ["--force-with-lease"], description: "Force the push, but only if the upstream is in the expected state" },
				{ name: ["--all"], description: "Push all branches" },
				{ name: ["--tags"], description: "Push all tags" },
				{ name: ["--no-tags"], description: "Don't push tags" },
				{ name: ["-q", "--quiet"], description: "Be quiet" },
				{ name: ["-v", "--verbose"], description: "Be verbose" },
			],
		},
		{
			name: "status",
			description: "Show the working tree status",
			options: [
				{ name: ["-s", "--short"], description: "Give the output in the short format" },
				{ name: ["--branch"], description: "Show the branch and tracking info even in short format" },
				{ name: ["--porcelain"], description: "Give the output in an easy-to-parse format for scripts" },
				{ name: ["--long"], description: "Give the output in the long format (default)" },
				{ name: ["-u", "--untracked-files"], description: "Show untracked files", arguments: [{ name: "mode" }] },
			],
		},
		{
			name: "remote",
			description: "Manage set of tracked repositories",
			subcommands: [
				{
					name: "add",
					description: "Add a new remote",
					arguments: [
						{ name: "name", description: "Name of the remote" },
						{ name: "url", description: "URL of the remote" },
					],
				},
				{
					name: "remove",
					alias: ["rm"],
					description: "Remove the remote named <name>",
					arguments: [
						{ name: "name", description: "Name of the remote to remove" },
					],
				},
				{
					name: "list",
					alias: ["ls"],
					description: "List remotes",
				},
				{
					name: "show",
					description: "Show information about a remote",
					arguments: [
						{ name: "name", description: "Name of the remote", optional: true },
					],
				},
			],
		},
		{
			name: "cherry-pick",
			description: "Apply the changes introduced by some existing commits",
			options: [
				{ name: ["-e", "--edit"], description: "Edit the commit message prior to committing" },
				{ name: ["-x"], description: "Append the commit hash to the original message" },
				{ name: ["--continue"], description: "Continue the operation in progress" },
				{ name: ["--abort"], description: "Cancel the operation and return to the pre-sequence state" },
				{ name: ["--skip"], description: "Skip the current commit and continue with the rest" },
			],
		},
		{
			name: "branch",
			description: "List, create, or delete branches",
			arguments: [
				{
					name: "branchname",
					description: "Branch to create or delete",
					optional: true,
				},
			],
			options: [
				{ name: ["-a", "--all"], description: "List both remote-tracking and local branches" },
				{ name: ["-d", "--delete"], description: "Delete fully merged branches" },
				{ name: ["-D"], description: "Force delete branches" },
				{ name: ["-m", "--move"], description: "Move/rename a branch" },
				{ name: ["-r", "--remotes"], description: "List or delete the remote-tracking branches" },
			],
		},
		{
			name: "log",
			description: "Show commit logs",
			options: [
				{ name: ["--oneline"], description: "Show each commit on a single line" },
				{ name: ["--graph"], description: "Draw a text-based graph of commit history" },
				{ name: ["--all"], description: "Show all branches" },
				{ name: ["-n", "--max-count"], description: "Limit the number of commits to show", arguments: [{ name: "count" }] },
			],
		},
		{
			name: "diff",
			description: "Show changes between commits, commit and working tree, etc",
			arguments: [
				{
					name: "path",
					description: "Files and folders to diff",
					optional: true,
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
			options: [
				{ name: ["--staged", "--cached"], description: "Show the staged changes" },
				{ name: ["--stat"], description: "Show a diffstat instead of a full diff" },
			],
		},
		{
			name: "fetch",
			description: "Download objects and refs from another repository",
			arguments: [
				{
					name: "remote",
					description: "Remote to fetch from",
					optional: true,
				},
			],
			options: [
				{ name: ["--all"], description: "Fetch all remotes" },
				{ name: ["-p", "--prune"], description: "Prune remote-tracking branches no longer on remote" },
				{ name: ["--tags"], description: "Fetch all tags" },
			],
		},
		{
			name: "pull",
			description: "Fetch from and integrate with another repository or a local branch",
			arguments: [
				{
					name: "remote",
					description: "Remote to pull from",
					optional: true,
				},
			],
			options: [
				{ name: ["--rebase"], description: "Rebase the current branch on top of the upstream branch" },
				{ name: ["--no-rebase"], description: "Do not rebase the current branch" },
				{ name: ["--ff-only"], description: "Only allow fast-forward updates" },
				{ name: ["-q", "--quiet"], description: "Be quiet" },
			],
		},
		{
			name: "merge",
			description: "Join two or more development histories together",
			arguments: [
				{
					name: "branch",
					description: "Branch or commit to merge in",
					arity: {},
				},
			],
			options: [
				{ name: ["--no-ff"], description: "Create a merge commit even when fast-forward is possible" },
				{ name: ["--squash"], description: "Squash the changes into a single commit" },
				{ name: ["--abort"], description: "Abort the current conflict resolution process" },
			],
		},
		{
			name: "reset",
			description: "Reset current HEAD to the specified state",
			arguments: [
				{
					name: "pathspec",
					description: "Files and folders to reset",
					optional: true,
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
			options: [
				{ name: ["--soft"], description: "Don't touch the index file or the working tree" },
				{ name: ["--mixed"], description: "Reset the index but not the working tree (default)" },
				{ name: ["--hard"], description: "Reset the index and the working tree" },
			],
		},
		{
			name: "stash",
			description: "Stash the changes in a dirty working directory away",
			subcommands: [
				{
					name: "push",
					description: "Save the working tree state",
				},
				{
					name: "pop",
					description: "Restore the stashed state",
				},
				{
					name: "list",
					description: "List the stashed states",
				},
				{
					name: "drop",
					description: "Drop a stashed state",
					arguments: [
						{ name: "stash", description: "Stash to drop", optional: true },
					],
				},
				{
					name: "show",
					description: "Show a stashed state",
					arguments: [
						{ name: "stash", description: "Stash to show", optional: true },
					],
				},
			],
		},
		{
			name: "tag",
			description: "Create, list, delete or verify a tag object",
			arguments: [
				{
					name: "tagname",
					description: "Name of the tag",
					optional: true,
				},
			],
			options: [
				{ name: ["-a", "--annotate"], description: "Create an annotated tag" },
				{ name: ["-d", "--delete"], description: "Delete a tag" },
				{ name: ["-l", "--list"], description: "List tags" },
				{ name: ["-f", "--force"], description: "Force the operation" },
			],
		},
		{
			name: "rebase",
			description: "Reapply commits on top of another base tip",
			arguments: [
				{
					name: "upstream",
					description: "Upstream branch to rebase onto",
					optional: true,
				},
			],
			options: [
				{ name: ["-i", "--interactive"], description: "Open an interactive rebase" },
				{ name: ["--continue"], description: "Continue the rebase" },
				{ name: ["--abort"], description: "Abort the rebase" },
				{ name: ["--skip"], description: "Skip the current commit" },
			],
		},
	],
	options: [
		{ name: ["-C"], description: "Run as if git was started in the given path", arguments: [{ name: "path" }] },
		{ name: ["-c"], description: "Pass a configuration parameter to the command", arguments: [{ name: "name=value" }] },
		{ name: ["--git-dir"], description: "Set the path to the repository", arguments: [{ name: "path" }] },
		{ name: ["--work-tree"], description: "Set the path to the working tree", arguments: [{ name: "path" }] },
		{ name: ["--no-pager"], description: "Do not pipe output into a pager" },
		{ name: ["--bare"], description: "Treat the repository as a bare repository" },
		{ name: ["--version"], description: "Print the git version" },
		{ name: ["--help"], description: "Print the synopsis and a list of the most commonly used commands" },
	],
};
