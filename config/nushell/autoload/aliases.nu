# shell
alias core-cd = cd
alias cd = core-cd --physical
alias cdp = cd -

# system
alias s = sudo
alias se = sudo -E
alias sv = sudoedit
alias sev = sudoedit

# nvim
alias v = nvim
alias vs = nvim +SessionLoad

# processes
alias pk = pkill --count --echo
alias pkk = pkill --count --echo -KILL
alias pga = pgrep -a

# misc
alias zj = zellij

# docs
alias m = man

# utilities
alias md = gh markdown-preview -p 6419 --disable-auto-open
alias serve = python -m http.server
alias icat = kitty +kitten icat

# ai
alias oc = opencode
