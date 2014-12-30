# This script is intended to be sourced from zsh.
precmd () {
    PROMPT="$(shellprompt encode zsh || echo "$ ")"
}
