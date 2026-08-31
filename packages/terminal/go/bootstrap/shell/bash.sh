if [ -n "${__OPERATOR_TERMINAL_LOADED:-}" ]; then
	return 0 2>/dev/null || exit 0
fi
__OPERATOR_TERMINAL_LOADED=1
__operator_terminal_BOOTSTRAP_SOURCE=${BASH_SOURCE[0]}
__operator_terminal_COUNTER=0
__operator_terminal_PROMPT_PHASE=1
__operator_terminal_INITIAL_PROMPT=1

__operator_terminal_pct_encode() {
	local s=$1 out='' i ch encoded
	for ((i = 0; i < ${#s}; i++)); do
		ch=${s:i:1}
		case $ch in
			[A-Za-z0-9._~/:@!\$\&\(\)\*\+,-]) out+=$ch ;;
			*) printf -v encoded '%%%02x' "'$ch"; out+=$encoded ;;
		esac
	done
	printf '%s' "$out"
}

__operator_terminal_branch() {
	command -v git >/dev/null 2>&1 || return 0
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	git rev-parse --abbrev-ref HEAD 2>/dev/null
}

__operator_terminal_next_id() {
	local handle=${OPERATOR_TERMINAL_ID:-terminal}
	handle=${handle//[^A-Za-z0-9_-]/_}
	[ -n "$handle" ] || handle=terminal
	__operator_terminal_COUNTER=$((__operator_terminal_COUNTER + 1))
	__operator_terminal_CURRENT_ID="${handle}-${__operator_terminal_COUNTER}"
}

__operator_terminal_preexec() {
	local command=$1 encoded
	encoded=$(__operator_terminal_pct_encode "$command")
	printf '\033]7000;v=1;id=%s;cmd=%s\033\\' "$__operator_terminal_CURRENT_ID" "$encoded"
	printf '\033]7000;v=1;input-released=1\007'
	printf '\033]133;C\007'
	__operator_terminal_COMMAND_RUNNING=1
}

__operator_terminal_precmd() {
	local code=$1 cwd branch
	if [ "${OPERATOR_TERMINAL_SUPPRESS_PROMPT:-0}" = 1 ]; then
		PS1=''
	fi
	if [ "${__operator_terminal_COMMAND_RUNNING:-0}" = 1 ]; then
		printf '\033]7000;v=1;id=%s;exit=%s\033\\' "$__operator_terminal_CURRENT_ID" "$code"
		printf '\033]133;D;%s\007' "$code"
		unset __operator_terminal_COMMAND_RUNNING
	fi
	if [ "${__operator_terminal_INITIAL_PROMPT:-0}" = 1 ]; then
		printf '\033]7000;v=1;exit=%s\007' "$code"
		unset __operator_terminal_INITIAL_PROMPT
	fi
	__operator_terminal_next_id
	cwd=$(__operator_terminal_pct_encode "$PWD")
	branch=$(__operator_terminal_pct_encode "$(__operator_terminal_branch)")
	printf '\033]7000;v=1;id=%s;cwd=%s;branch=%s\033\\' "$__operator_terminal_CURRENT_ID" "$cwd" "$branch"
	printf '\033]133;A\007'
	printf '\033]133;B\007'
	printf '\033]7000;v=1;input-ready=1\007'
}

__operator_terminal_prompt_command() {
	local code=$?
	__operator_terminal_IN_HOOK=1
	__operator_terminal_PROMPT_PHASE=1
	if [ -n "${__operator_terminal_existing_prompt_command:-}" ]; then
		eval "$__operator_terminal_existing_prompt_command"
	fi
	__operator_terminal_precmd "$code"
	unset __operator_terminal_IN_HOOK
	return "$code"
}

__operator_terminal_history_command() {
	local entry
	entry=$(builtin history 1)
	if [[ $entry =~ ^[[:space:]]*[0-9]+[[:space:]]+(.*)$ ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return
	fi
	printf '%s' "$BASH_COMMAND"
}

__operator_terminal_debug() {
	local command=$BASH_COMMAND
	[ "${__operator_terminal_IN_HOOK:-0}" = 1 ] && return
	[ "${__operator_terminal_INITIALIZING:-0}" = 1 ] && return
	case ${FUNCNAME[1]:-} in
		__operator_terminal_*) return ;;
	esac
	case $command in
		__operator_terminal_*) return ;;
		*"$__operator_terminal_BOOTSTRAP_SOURCE"*) return ;;
	esac
	if [ "${__operator_terminal_PROMPT_PHASE:-0}" = 1 ]; then
		__operator_terminal_PROMPT_PHASE=0
	fi
	[ "${__operator_terminal_COMMAND_RUNNING:-0}" = 1 ] && return
	local submitted_command
	submitted_command=$(__operator_terminal_history_command)
	case $submitted_command in
		*"$__operator_terminal_BOOTSTRAP_SOURCE"*) return ;;
	esac
	__operator_terminal_IN_HOOK=1
	__operator_terminal_preexec "$submitted_command"
	unset __operator_terminal_IN_HOOK
}

__operator_terminal_existing_prompt_command=${PROMPT_COMMAND:-}
__operator_terminal_existing_debug_spec=$(trap -p DEBUG)
__operator_terminal_INITIALIZING=1
if [ -n "$__operator_terminal_existing_debug_spec" ]; then
	__operator_terminal_existing_debug_spec=${__operator_terminal_existing_debug_spec#trap -- }
	__operator_terminal_existing_debug_spec=${__operator_terminal_existing_debug_spec% DEBUG}
	trap "$__operator_terminal_existing_debug_spec; __operator_terminal_debug" DEBUG
else
	trap '__operator_terminal_debug' DEBUG
fi
shopt -s cmdhist lithist
PROMPT_COMMAND=__operator_terminal_prompt_command
unset __operator_terminal_INITIALIZING
if [ -n "$__operator_terminal_existing_debug_spec" ]; then
	__operator_terminal_preexec "$BASH_COMMAND"
fi
