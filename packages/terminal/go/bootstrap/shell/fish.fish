if set -q __OPERATOR_TERMINAL_LOADED
	return 0
end
set -g __OPERATOR_TERMINAL_LOADED 1

if functions -q fish_prompt
	functions -c fish_prompt __operator_terminal_user_fish_prompt
end

function __operator_terminal_pct_encode
	printf '%s' $argv[1] | string escape --style=url
end

function __operator_terminal_prompt --on-event fish_prompt
	if test "$OPERATOR_TERMINAL_SUPPRESS_PROMPT" = 1
		function fish_prompt
		end
	else if functions -q __operator_terminal_user_fish_prompt
		functions -e fish_prompt
		functions -c __operator_terminal_user_fish_prompt fish_prompt
	end
	set -l cwd (__operator_terminal_pct_encode $PWD)
	set -l branch ""
	if command -q git
		set -l head (git rev-parse --abbrev-ref HEAD 2>/dev/null)
		if test $status -eq 0
			set branch (__operator_terminal_pct_encode $head)
		end
	end
	printf '\e]7000;v=1;cwd=%s;branch=%s\a' $cwd $branch
	printf '\e]7000;v=1;input-ready=1\a'
end

function __operator_terminal_preexec --on-event fish_preexec
	set -l cmd (__operator_terminal_pct_encode $argv[1])
	printf '\e]7000;v=1;cmd=%s\a' $cmd
	printf '\e]7000;v=1;input-released=1\a'
end

function __operator_terminal_postexec --on-event fish_postexec
	printf '\e]7000;v=1;exit=%s\a' $status
end
