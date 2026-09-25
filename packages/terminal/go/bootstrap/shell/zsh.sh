__operator_terminal_guard() {
	emulate -L zsh
	[[ -n ${__OPERATOR_TERMINAL_LOADED:-} ]] && return 0
	__OPERATOR_TERMINAL_LOADED=1

	typeset -gr __operator_terminal_SAFE='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~/:@!$&()*+,-'

	typeset -gi __operator_terminal_COUNTER=0

	autoload -Uz add-zsh-hook 2>/dev/null

	typeset -gri __operator_terminal_TYPEAHEAD_MAX=256

	__operator_terminal_input_ready() {
		emulate -L zsh
		print -nr -- $'\e]133;B\a'
		print -nr -- $'\e]7000;v=1;input-ready=1\a'
		__operator_terminal_report_typeahead
	}

	__operator_terminal_report_typeahead() {
		emulate -L zsh
		[[ ${__operator_terminal_TYPEAHEAD_ARMED:-0} == 1 ]] || return 0
		unset __operator_terminal_TYPEAHEAD_ARMED
		[[ $CONTEXT == start ]] || return 0
		local typed='' key
		while (( ${#typed} <= __operator_terminal_TYPEAHEAD_MAX )) && read -t 0 -k 1 key; do
			typed+=$key
		done
		[[ -n $typed ]] || return 0
		zle -U -- "$typed"
		(( ${#typed} <= __operator_terminal_TYPEAHEAD_MAX )) || return 0
		[[ $typed != *[[:cntrl:]]* ]] || return 0
		print -nr -- $'\e]7000;v=1;typeahead='"$(__operator_terminal_pct_encode "$typed")"$'\a'
	}

	__operator_terminal_input_released() {
		emulate -L zsh
		print -nr -- $'\e]7000;v=1;input-released=1\a'
	}

	if autoload -Uz add-zle-hook-widget 2>/dev/null; then
		zle -N __operator_terminal_input_ready
		add-zle-hook-widget line-init __operator_terminal_input_ready
	fi

	add-zsh-hook preexec __operator_terminal_input_released

	__operator_terminal_pct_encode() {
		emulate -L zsh
		setopt no_multibyte
		local s=$1 out='' ch encoded
		local -i i
		for ((i = 1; i <= ${#s}; i++)); do
			ch=${s[i]}
			if [[ $__operator_terminal_SAFE == *"$ch"* ]]; then
				out+=$ch
			else
				printf -v encoded '%%%02x' "'$ch"
				out+=$encoded
			fi
		done
		print -nr -- $out
	}

	__operator_terminal_next_id() {
		emulate -L zsh
		local handle=${OPERATOR_TERMINAL_ID:-terminal}
		handle=${handle//[^A-Za-z0-9_-]/_}
		[[ -n $handle ]] || handle=terminal
		__operator_terminal_COUNTER=$(( __operator_terminal_COUNTER + 1 ))
		__operator_terminal_CURRENT_ID="${handle}-${__operator_terminal_COUNTER}"
	}

	__operator_terminal_branch() {
		emulate -L zsh
		command -v git >/dev/null 2>&1 || return 0
		git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
		local b
		b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
		print -nr -- $b
	}

	__operator_terminal_preexec() {
		emulate -L zsh
		local cmd=$(__operator_terminal_pct_encode "$1")
		print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';cmd='${cmd}$'\e\\'
		print -nr -- $'\e]7000;v=1;input-released=1\a'
		print -nr -- $'\e]133;C\a'
		__operator_terminal_COMMAND_RUNNING=1
	}

	__operator_terminal_precmd() {
		local __operator_terminal_status=$?
		emulate -L zsh
		if [[ ${OPERATOR_TERMINAL_SUPPRESS_PROMPT:-0} == 1 ]]; then
			PROMPT=''
			RPROMPT=''
		fi
		if [[ ${__operator_terminal_COMMAND_RUNNING:-0} == 1 ]]; then
			print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';exit='${__operator_terminal_status}$'\e\\'
			print -nr -- $'\e]133;D;'${__operator_terminal_status}$'\a'
			unset __operator_terminal_COMMAND_RUNNING
			__operator_terminal_TYPEAHEAD_ARMED=1
		fi
		__operator_terminal_next_id
		local cwd branch
		cwd=$(__operator_terminal_pct_encode "$PWD")
		branch=$(__operator_terminal_pct_encode "$(__operator_terminal_branch)")
		print -nr -- $'\e]7000;v=1;id='${__operator_terminal_CURRENT_ID}$';cwd='${cwd}$';branch='${branch}$'\e\\'
		print -nr -- $'\e]133;A\a'
	}

	add-zsh-hook precmd __operator_terminal_precmd
	add-zsh-hook preexec __operator_terminal_preexec
}

__operator_terminal_guard
