# Get the current word to be completed (assumes cursor is at the end of the word)
export def get-current-word [context: string, position: int] {
  let sep = '(\s+|=)'
  if ($context | split chars | get -o ($position - 1)) =~ $"^($sep)$" {
    return ""
  }
  $context | split row -r $sep | last
}

# Completion helper for comma-separated options, e.g.
#   mycmd --opt=foo,bar
#   mycmd --opt foo,bar
#   mycmd -o foo,bar
export def complete-comma-separated-options [
  context: string, # Context string
  position: int, # Position of the cursor
  options: list<string>, # List of options for completion
] {
  let context = get-current-word $context $position
  let selected = $context | split row "," | str trim | where { is-not-empty }
  let candidates = $options | where { $in not-in $selected }
  if ($candidates | is-empty) {
    return []
  }

  let active = if ($selected | is-not-empty) and not ($context | str ends-with ",") {
    let last = $selected | last
    if ($last not-in $options) { $last }
  }
  let active_incomplete = ($active | is-not-empty) and $active not-in $candidates

  let candidates = if $active_incomplete {
    $candidates | where { $in | str starts-with $active }
  } else { $candidates }

  let selected = if $active_incomplete {
    $selected | take (($selected | length) - 1)
  } else { $selected }

  $candidates | each { $selected ++ [$in] | str join "," }
}
