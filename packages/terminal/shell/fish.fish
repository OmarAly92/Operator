if set -q __OPERATOR_TERMINAL_LOADED
	return 0
end
set -g __OPERATOR_TERMINAL_LOADED 1
set -g __operator_terminal_counter 0

if functions -q fish_prompt
	functions -c fish_prompt __operator_terminal_user_fish_prompt
end

function __operator_terminal_pct_encode
	printf '%s' $argv[1] | string escape --style=url
end

function __operator_terminal_branch
	command -q git; or return 0
	git rev-parse --is-inside-work-tree >/dev/null 2>/dev/null; or return 0
	git rev-parse --abbrev-ref HEAD 2>/dev/null
end

function __operator_terminal_next_id
	set -l terminal_handle $OPERATOR_TERMINAL_ID
	if test -z "$terminal_handle"
		set terminal_handle terminal
	end
	set terminal_handle (string replace -ar '[^A-Za-z0-9_-]' '_' -- $terminal_handle)
	if test -z "$terminal_handle"
		set terminal_handle terminal
	end
	set -g __operator_terminal_counter (math $__operator_terminal_counter + 1)
	set -g __operator_terminal_current_id "$terminal_handle-$__operator_terminal_counter"
end

function __operator_terminal_open_block
	__operator_terminal_next_id
	set -l cwd (__operator_terminal_pct_encode $PWD)
	set -l branch (__operator_terminal_pct_encode (__operator_terminal_branch))
	printf '\e]7000;v=1;id=%s;cwd=%s;branch=%s\e\\' $__operator_terminal_current_id $cwd $branch
end

function __operator_terminal_prompt --on-event fish_prompt
	if test "$OPERATOR_TERMINAL_SUPPRESS_PROMPT" = 1
		function fish_prompt
		end
	else if functions -q __operator_terminal_user_fish_prompt
		functions -e fish_prompt
		functions -c __operator_terminal_user_fish_prompt fish_prompt
	end
	if not set -q __operator_terminal_current_id
		__operator_terminal_open_block
	end
	printf '\e]7000;v=1;input-ready=1\a'
end

function __operator_terminal_preexec --on-event fish_preexec
	set -l command (__operator_terminal_pct_encode $argv[1])
	printf '\e]7000;v=1;id=%s;cmd=%s\e\\' $__operator_terminal_current_id $command
	printf '\e]7000;v=1;input-released=1\a'
	set -g __operator_terminal_command_running 1
end

function __operator_terminal_finish_block
	set -l code $argv[1]
	if not set -q __operator_terminal_command_running
		return
	end
	printf '\e]7000;v=1;id=%s;exit=%s\e\\' $__operator_terminal_current_id $code
	set -e __operator_terminal_command_running
	__operator_terminal_open_block
end

function __operator_terminal_postexec --on-event fish_postexec
	set -l code $status
	__operator_terminal_finish_block $code
end

function __operator_terminal_posterror --on-event fish_posterror
	set -l code $status
	__operator_terminal_finish_block $code
end
