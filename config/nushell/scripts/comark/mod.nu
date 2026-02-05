# Comark (Comma Bookmark) for Nushell
# Shell bookmark manager and file search utility for quick navigation and file management

export use core.nu *
export use fzf.nu *

# comark [alias] - with no args, opens fzf smart; with an alias, cd to bookmark
export def --env main [alias?: string@complete-alias] {
  if ($alias | is-empty) {
    fzf smart
  } else {
    cd $alias
  }
}
