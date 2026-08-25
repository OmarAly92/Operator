export type ImportFolderMode = "project" | "workspace";

export type ImportRepoScan = {
	name: string;
	path: string;
	relativePath: string;
	branch: string;
	remote: string;
	hasRemote: boolean;
	status?: "ok" | "error";
	reason?: string;
};

export type ImportFolderScan = {
	path: string;
	repos: ImportRepoScan[];
	setupWarning?: string;
};
