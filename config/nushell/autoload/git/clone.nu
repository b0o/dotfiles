# Git clone with smart defaults
export def gcl [...args] {
  mut opts = ["--recurse-submodules"]
  mut positional = []

  # Separate options from positional arguments
  for item in $args {
    if ($item | str starts-with "-") {
      $opts = ($opts | append $item)
    } else {
      $positional = ($positional | append $item)
    }
  }

  mut dest = ""

  # Determine destination based on arguments
  if ($positional | length) == 1 {
    let repo = ($positional | get 0)
    let git_dir = ($env.GIT_PROJECTS_DIR? | default ([$env.HOME "git"] | path join))
    $dest = ([$git_dir ($repo | path basename)] | path join)
    $positional = [$repo $dest]
  } else if ($positional | length) == 2 and ($positional | get 1) == "." {
    let repo = ($positional | get 0)
    $dest = ($repo | path basename)
    $positional = [$repo $dest]
  } else if ($positional | length) >= 2 {
    $dest = ($positional | get 1)
  }

  # Check if we should clone
  let should_clone = if ($dest | is-empty) {
    true
  } else if not ($dest | path exists) {
    true
  } else if ($dest | path type) != "dir" {
    true
  } else {
    let has_git = ([$dest ".git"] | path join | path exists)
    let has_head = ([$dest "HEAD"] | path join | path exists)
    not $has_git and not $has_head
  }

  if $should_clone {
    let git_args = ($opts | append $positional)
    do { git clone ...$git_args }
  } else {
    print -e "Skipping clone: Repository already exists"
  }

  $dest
}

# Git clone and cd
export def --env gccl [...args] {
  let dest = (gcl ...$args)
  cd $dest
}

# Execute git command in worktree
export def gwx [
  ...git_args               # Git command and arguments
  --current (-c)            # Use current worktree
  --worktree (-w): string   # Use specified worktree
] {
  let w = if $current {
    # Note: This requires gwc (get worktree current) to be implemented
    # gwc -p should return the path of the current worktree
    let result = (^gwc -p | complete)
    if $result.exit_code != 0 {
      error make {msg: "failed to get current worktree"}
    }
    $result.stdout | str trim
  } else if $worktree != null {
    # Use gw-select to get the specified worktree
    let selection = (gw-select $worktree)
    if $selection == null {
      error make {msg: "failed to select worktree"}
    }
    $selection.path
  } else {
    # Interactive selection
    let selection = (gw-select)
    if $selection == null {
      error make {msg: "no worktree selected"}
    }
    $selection.path
  }

  if ($w | is-empty) {
    error make {msg: "no worktree path determined"}
  }

  # Execute git command in worktree directory
  git -C $w ...$git_args
}
