# Git clone with smart defaults
export def --wrapped  gcl [...args] {
  mut opts = ["--recurse-submodules"]
  mut positional = []
  mut is_bare = false
  # Separate options from positional arguments
  for item in $args {
    if ($item | to text | str starts-with "-") {
      $opts = ($opts | append $item)
      if $item == "--bare" {
        $is_bare = true
      }
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
    $dest = ($positional | get 1 | path expand)
    if ($dest | path exists) and ($dest | path type) == "dir" and (ls -a $dest | is-not-empty) {
      let repo = ($positional | get 0)
      $dest = ([$dest ($repo | path basename)] | path join)
    }
    $positional = ($positional | update 1 $dest)
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
    # Fix fetch refspec for bare clones
    if $is_bare and not ($dest | is-empty) {
      git -C $dest config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    }
  } else {
    print -e "Skipping clone: Repository already exists"
  }
  $dest
}

# Git clone and cd
export def --env --wrapped gccl [...args] {
  let dest = (gcl ...$args)
  cd $dest
}
