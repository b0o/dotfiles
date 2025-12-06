export def gig [
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
