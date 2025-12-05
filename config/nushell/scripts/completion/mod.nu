use candidates.nu
use context.nu

def column-width [candidates: table, column: cell-path, --padding: int = 2]: nothing -> int {
    (
      $candidates
        | get $column
        | each {str length}
        | math max
    ) + $padding
}

export def fuzzy-complete-dwim [context: record]: nothing -> string {
  # TODO: preview with usage (available in metadata for internals, and tldr for externals)
  let candidates = (candidates for-context $context)
  if ($candidates | is-empty) {
    return ""
  }
  let name_width = (column-width $candidates name)
  $candidates
    | (sk
      --multi
      --prompt "  "
      --query ($context.token | default {content: ""} | get content)
      --height "50%"
      --select-1
      --exit-0
      --format {
        $"($in.name | fill -w $name_width)($in.description)"
      })
    | default [{ name: "" }]
    | get name
    | str join " "
}

def replace-current-token [context: record, replacement: string] {
  if ($context.token | is-empty) {
    [$context.pipeline, $replacement] | str join ""
  } else  {
    let before = $context.pipeline | str substring ..<$context.token.span.start
    let after = $context.pipeline | str substring $context.token.span.end..
    [$before, $replacement, $after] | str join ""
  }
}

export def commandline-fuzzy-complete-dwim [] {
  let context = (context current-completion-context)
  let selected = (fuzzy-complete-dwim $context)
  if ($selected | is-not-empty) {
    commandline edit --replace (replace-current-token $context $selected)
  }
}
