if [ -r "$HOME/.bashrc" ]; then
	source "$HOME/.bashrc"
fi
source "${BASH_SOURCE[0]%/*}/../bash.sh"
