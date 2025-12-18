# Git push with smart default remote and branch
# If no remote is specified, use "origin" or the first remote with "push" access
# If no branch is specified, use the current branch
export def --wrapped gpp [
  ...args: string
] {
  mut opts = []
  mut positional = []
  for item in $args {
    if ($item | to text | str starts-with "-") {
      $opts = $opts | append $item
    } else {
      $positional = $positional | append $item
    }
  }
  if ($positional | length) < 2 {
    let remotes = (git remote -v
    | lines
    | each { parse --regex '(?<remote>\S+)\s+(?<url>\S+)\s+\((?<kind>\w+)\)' }
    | flatten
    | where kind == 'push')
    let default_remote = if ($remotes | any { $in.remote == "origin" }) {
      "origin"
    } else {
      $remotes | first | get remote
    }
    let default_branch = (^git rev-parse --abbrev-ref HEAD)
    if ($positional | length) == 0 {
      $positional = [$default_remote $default_branch]
    } else if ($positional | length) == 1 {
      $positional = ($positional | append $default_branch)
    }
  }
  git push ...$opts ...$positional
}
