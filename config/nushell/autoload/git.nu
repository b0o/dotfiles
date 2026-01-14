alias git = hub # important: set this before the `use` line so that we always use hub

export use git *

# see ~/.config/git/alias.config for git alias definitions
alias gl = git ls
alias gla = git la
alias gll = git ll
alias glla = git lla
alias glg = git lg

alias gst = git st
alias gd = git diff

alias ga = git add
alias gaa = git add --all
alias gai = git add --interactive

alias gp = git p
alias gpa = git pa
alias gpao = git pao

alias gc = git commit --verbose
alias gca = git commit --all --verbose
alias gcA = git commit --amend --verbose

alias gr = git remote --verbose

alias gtv = git tag-version

alias gigg = gig -w

alias gwc = cd (gw-current)
alias gwco = gw-current

alias gcclb = gccl --bare
