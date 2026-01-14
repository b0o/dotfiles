export use ./clone.nu *
export use ./ignore.nu *
export use ./worktree.nu *

def complete-g [spans: list<string>] {
  use nushell/completion.nu carapace-complete
  carapace-complete $spans hub
}

# git
@complete complete-g
export def --wrapped g [...args] {
  if ($args | is-empty) {
    git st
  } else {
    git ...$args
  }
}
