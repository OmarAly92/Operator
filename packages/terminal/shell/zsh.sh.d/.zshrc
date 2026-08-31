typeset __operator_terminal_integration_path="${ZDOTDIR:h}/zsh.sh"
typeset __operator_terminal_saved_zdotdir=${OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR:-$HOME}
ZDOTDIR=$__operator_terminal_saved_zdotdir
unset OPERATOR_TERMINAL_ORIGINAL_ZDOTDIR
if [[ -r $ZDOTDIR/.zshrc ]]; then
	source "$ZDOTDIR/.zshrc"
fi
source "$__operator_terminal_integration_path"
unset __operator_terminal_integration_path __operator_terminal_saved_zdotdir
