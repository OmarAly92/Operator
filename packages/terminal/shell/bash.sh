if [ -n "${__OPERATOR_TERMINAL_LOADED:-}" ]; then
	return 0 2>/dev/null || exit 0
fi
__OPERATOR_TERMINAL_LOADED=1

__operator_terminal_pct_encode() {
	local s=$1 out='' i ch
	for ((i = 0; i < ${#s}; i++)); do
		ch=${s:i:1}
		case $ch in
			[A-Za-z0-9._~/:@!\$\&\'\(\)\*\+,-]) out+=$ch ;;
			*) out+=$(printf '%%%02x' "'$ch") ;;
		esac
	done
	printf '%s' "$out"
}

__operator_terminal_precmd() {
	local code=$?
	printf '\033]7000;v=1;exit=%s\007' "$code"
	printf '\033]7000;v=1;cwd=%s\007' "$(__operator_terminal_pct_encode "$PWD")"
	printf '\033]7000;v=1;input-ready=1\007'
	return $code
}

__operator_terminal_preexec() {
	[ -n "${COMP_LINE:-}" ] && return
	printf '\033]7000;v=1;cmd=%s\007' "$(__operator_terminal_pct_encode "$BASH_COMMAND")"
	printf '\033]7000;v=1;input-released=1\007'
}

__operator_terminal_existing_debug_trap="$(trap -p DEBUG)"
__operator_terminal_existing_debug_trap="${__operator_terminal_existing_debug_trap#trap -- \'}"
__operator_terminal_existing_debug_trap="${__operator_terminal_existing_debug_trap%\' DEBUG}"
if [ -n "$__operator_terminal_existing_debug_trap" ]; then
	trap "$__operator_terminal_existing_debug_trap; __operator_terminal_preexec" DEBUG
else
	trap '__operator_terminal_preexec' DEBUG
fi

case ";${PROMPT_COMMAND:-};" in
	*";__operator_terminal_precmd;"*) ;;
	*) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}__operator_terminal_precmd" ;;
esac
