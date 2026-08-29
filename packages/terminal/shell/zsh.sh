__operator_terminal_guard() {
	emulate -L zsh
	[[ -n ${__OPERATOR_TERMINAL_LOADED:-} ]] && return 0
	__OPERATOR_TERMINAL_LOADED=1

	typeset -gr __operator_terminal_SAFE='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~/:@!$&'\'"'"'()*+,-'

	typeset -gi __operator_terminal_NEXT_ID=0

	autoload -Uz add-zsh-hook 2>/dev/null

	__operator_terminal_input_ready() {
		emulate -L zsh
		print -nr -- $'\e]7000;v=1;input-ready=1\a'
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
		local s=$1 out='' i ch code hi lo
		for ((i = 1; i <= ${#s}; i++)); do
			ch=${s[$i]}
			if [[ -n "${(M)__operator_terminal_SAFE##*${ch}*}" ]]; then
				out+=$ch
			else
				code=$(printf '%d' "'$ch")
				hi=$(( code >> 4 ))
				lo=$(( code & 0x0f ))
				out+='%'
				case $hi in
					0) out+='0' ;; 1) out+='1' ;; 2) out+='2' ;; 3) out+='3' ;;
					4) out+='4' ;; 5) out+='5' ;; 6) out+='6' ;; 7) out+='7' ;;
					8) out+='8' ;; 9) out+='9' ;; 10) out+='a' ;; 11) out+='b' ;;
					12) out+='c' ;; 13) out+='d' ;; 14) out+='e' ;; 15) out+='f' ;;
				esac
				case $lo in
					0) out+='0' ;; 1) out+='1' ;; 2) out+='2' ;; 3) out+='3' ;;
					4) out+='4' ;; 5) out+='5' ;; 6) out+='6' ;; 7) out+='7' ;;
					8) out+='8' ;; 9) out+='9' ;; 10) out+='a' ;; 11) out+='b' ;;
					12) out+='c' ;; 13) out+='d' ;; 14) out+='e' ;; 15) out+='f' ;;
				esac
			fi
		done
		print -nr -- $out
	}

	__operator_terminal_next_id() {
		emulate -L zsh
		__operator_terminal_NEXT_ID=$(( __OPERATOR_TERMINAL_LAST_ID + 1 ))
		__OPERATOR_TERMINAL_LAST_ID=$__operator_terminal_NEXT_ID
		local n=$__operator_terminal_NEXT_ID
		local hex='' d
		if (( n == 0 )); then
			hex='0'
		else
			while (( n > 0 )); do
				d=$(( n & 0x0f ))
				case $d in
					0) hex='0'$hex ;; 1) hex='1'$hex ;; 2) hex='2'$hex ;; 3) hex='3'$hex ;;
					4) hex='4'$hex ;; 5) hex='5'$hex ;; 6) hex='6'$hex ;; 7) hex='7'$hex ;;
					8) hex='8'$hex ;; 9) hex='9'$hex ;; 10) hex+='a' ;; 11) hex='b'$hex ;;
					12) hex='c'$hex ;; 13) hex='d'$hex ;; 14) hex='e'$hex ;; 15) hex='f'$hex ;;
				esac
				n=$(( n >> 4 ))
			done
		fi
		print -nr -- $hex
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
		__OPERATOR_TERMINAL_LAST_CMD=$1
		print -n '\e]133;C\a'
	}

	__operator_terminal_precmd() {
		emulate -L zsh
		local __operator_terminal_status=$?
		if [[ -n ${__OPERATOR_TERMINAL_LAST_CMD+x} ]]; then
			local id cmd cwd branch
			id=$(__operator_terminal_next_id)
			cmd=$(__operator_terminal_pct_encode "$__OPERATOR_TERMINAL_LAST_CMD")
			cwd=$(__operator_terminal_pct_encode "$PWD")
			branch=$(__operator_terminal_pct_encode "$(__operator_terminal_branch)")
			print -n -- $'\e]133;D;'${__operator_terminal_status}$'\a'
			print -n -- $'\e]7000;v=1;id='${id}$';cmd='${cmd}$';cwd='${cwd}$';branch='${branch}$';exit='${__operator_terminal_status}$'\e\\'
			unset __OPERATOR_TERMINAL_LAST_CMD
		fi
		print -n $'\e]133;A\a'
	}

	add-zsh-hook precmd __operator_terminal_precmd
	add-zsh-hook preexec __operator_terminal_preexec
}

__operator_terminal_guard
