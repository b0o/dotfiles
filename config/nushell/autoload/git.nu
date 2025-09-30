def gig [
  --write (-w)     # write to .gitignore
  ...args: string  # gitignore templates to fetch
] {
  # Check if in git repo when writing
  if $write {
    let git_check = (do --ignore-errors { ^git status } | complete)
    if $git_check.exit_code != 0 {
      error make {msg: "fatal: not a git repository"}
    }
  }

  # Build query string
  let q = ($args | str join ",")

  # Fetch gitignore rules
  let result = (
    ^curl -f -L -s $"https://www.toptal.com/developers/gitignore/api/($q)"
    | complete
  )

  if $result.exit_code != 0 {
    print -e $"Not found: ($q)"
    return
  }

  let content = $result.stdout

  if $write {
    # Append to .gitignore
    $content | save --append .gitignore
    print -e $"Updated .gitignore with rules for ($args | str join ' ')"
  } else {
    # Print to stdout
    print $content
  }
}

# see .gitconfig for git alias definitions
alias g = hub

alias gl = hub ls
alias gla = hub la
alias gll = hub ll
alias glla = hub lla
alias glg = hub lg

alias ga = hub add
alias gaa = hub add --all
alias gai = hub add --interactive

alias gpa = hub pa
alias gpao = hub pao

alias gc = hub commit --verbose
alias gca = hub commit --all --verbose
alias gcA = hub commit --amend --verbose

alias gr = hub remote --verbose

alias gtv = hub tag-version

alias gigg = gig -w
