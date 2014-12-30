# This script is intended to be sourced from tcsh.
alias precmd 'set prompt = "`shellprompt encode tcsh || echo %`"'
