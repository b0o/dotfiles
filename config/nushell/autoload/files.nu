# Smart & pretty file and directory lister using eza and bat
export def l [
  --levels (-L): int = 1  # Levels of depth to display (for directories)
  ...args: path           # Target files or directories to list
] {
  # Collect all targets from args and pipeline
  let targets = (
    if $in == null {
      # No pipeline input
      if ($args | is-empty) { ["."] } else { $args }
    } else {
      # Has pipeline input - combine with args
      let from_pipeline = ($in | lines)
      if ($args | is-empty) {
        $from_pipeline
      } else {
        [...$args, ...$from_pipeline]
      }
    }
  )

  # Process each target
  for $target in $targets {
    if not ($target | path exists) {
      error make -u {msg: $"Target does not exist: ($target)"}
    }
    let expanded = ($target | path expand)
    match ($expanded | path type) {
      "dir" => {
        ^eza -algF --git --group-directories-first -TL $levels -- $expanded
      }
      "file" => {
        ^bat -- $expanded
      }
    }
  }
}

# mkdir and cd
export def --env mcd [
  ...args: string
] {
  let dir = ($args | path join)
  mkdir $dir
  cd $dir
}

alias l1 = l -L 1
alias l2 = l -L 2
alias l3 = l -L 3
alias l4 = l -L 4
alias l5 = l -L 5
alias l6 = l -L 6
alias l7 = l -L 7
alias l8 = l -L 8
alias l9 = l -L 9

alias cx = chmod +x
alias tf = tail -f
alias cat = bat
alias duh = du -h
alias dfh = df -h
alias mcdt = mcd /tmp
