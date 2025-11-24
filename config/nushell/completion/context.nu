use candidates.nu

# Returns a flattened AST for `pipeline` with an index column
export def flat-ast [pipeline: string] {
    ast $pipeline --flatten | enumerate | flatten
}

# Returns the index of the (flattened) AST token containing the character at
# index `char_index` in the AST's source code
export def char-to-token-index [ast: table, char_index: int] {
    # Find the index of the token that contains the character at `position`
    let token_index = (
      $ast
      | where ($it.span.start <= $char_index) and ($char_index <= $it.span.end)
    )

    if ($token_index | is-empty) {
      null
    } else {
      $token_index
        | first
        | get "index"
    }
}

# Expands a command if it is an alias (otherwise returns the command as-is)
export def expand-alias [command?: string]: [nothing -> string, string -> string] {
    let command = if ($command | is-not-empty) { $command } else { $in }
    let alias_info = (scope aliases | where name == $command)
    if ($alias_info | is-empty) { 
      return $command
    }
    $alias_info 
      | first 
      | get expansion 
      | ast $in --flatten 
      | first 
      | get content 
}

# Returns the name of the command closest to `position` in `pipeline`
export def command-at-position [pipeline: string, position: int, --expand-alias]: nothing -> record {
    let ast = (flat-ast $pipeline)
    let cursor_token = (char-to-token-index $ast $position)

    # Trailing `|` is discarded by `ast` at the time of writing, so we special-case it here:
    if ($ast | is-empty) or (($cursor_token | is-empty) and ($pipeline | str trim | str ends-with "|")) {
      return null
    }

    # Get the pipe segment that contains the token
    let segment = (
      if ($cursor_token | is-empty) {
        $ast 
          | where {|row| $row.shape in ["shape_internalcall" "shape_external"]}
          | last 1
      } else {
        $ast
          | where "index" <= $cursor_token
          | sort-by index -r
          | take until {|row| $row.shape in ["shape_pipe" "shape_closure"]}
          | where {|row| $row.shape in ["shape_internalcall" "shape_external"]}
      }
    ) 

    if ($segment | is-empty) {
      null
    } else {
      let s = ($segment | first)
      {
        name: (if $expand_alias { expand-alias $s.content } else { $s.content }), 
        type: (if $s.shape == "shape_internalcall" { "internal" } else { "external" })
      }
    }
}

# Returns a list of possible completion types for a cursor at index `cursor` in
# of `pipeline`. The return structure is a list of lists, each list corresponds
# to a set of completion candidate types that should be generated in order until
# at least one candidate is generated.
#
# For example: `[["SUBCOMMAND"], ["PATH", "SHORT_FLAG"]]`
# This means the completion provider should first generate a list of only subcommands,
# and if there are no subcommand candidates, then try to generate a list that contains
# both path and short flag candidates.
export def completion-context [pipeline: string, cursor: int]: nothing -> record {
    let pipeline = (commandline)
    let ast = (flat-ast $pipeline)
    let cursor_index = (commandline get-cursor) 
    let token_index = (char-to-token-index $ast $cursor_index)

    mut token = null
    mut prev_token = null
    if ($ast | is-empty) {
      # (both stay null)
    } else if ($token_index | is-empty) {
      $prev_token = $ast | last
    } else if ($token_index == 0) {
      $token = $ast | first
    } else {
      $token = $ast | get $token_index 
      $prev_token = $ast | get ($token_index - 1)
    }
    let prev_char = $pipeline | str substring ($cursor_index - 1)..($cursor_index - 1)

    # If the current token starts with any of these special characters,
    # then we use the corresponding completion types, regardless of what
    # the rest of the context
    let t_or_empty = $token | default {content: ""} | get content
    let prefix_matched_types = (
      match ($t_or_empty | str substring ..0) {
        _ if ($t_or_empty | str starts-with "./") or ($t_or_empty | str ends-with "/") => [["PATH"]]
        _ if ($t_or_empty | str starts-with "./") or ($t_or_empty | str ends-with "/") => [["PATH"]]
        "" if ($prev_char == "^") => [["EXTERNAL_COMMAND"]]
        "/" | "~" => [["PATH"]]
        "." => [["COMMAND", "PATH"]]
        "$" => [["VAR", "ENV"]]
        "-" if ($t_or_empty | str starts-with "--") => [["LONG_FLAG"]]
        "-" => [["FLAG"]]
        "{" if ($t_or_empty | str ends-with "|") => [["COMMAND"]] # closure
        _ => null
      }
    )

    let default_types = ["FLAG", "PATH"]
    let completion_types = match [$prev_token, $token, $prefix_matched_types] {
      [null, null, _] | [null, $t, null] => [["COMMAND"]]
      [$p, $t, null] => {
        match ($p | get shape) {
          "shape_internalcall" | "shape_external" => [["SUBCOMMAND"], $default_types]
          "shape_flag" => [["FLAG_ARG"], $default_types] 
          "shape_externalarg" if ($p | get content | str starts-with "-") => [["FLAG_ARG"], $default_types] 
          "shape_variable" if ($prev_char  == ".") => [["ATTR"]] 
          _ => [$default_types]
        }
      }
      [_, _, $pm] => ($pm | default [["COMMAND"]])
    }

    {
      pipeline: $pipeline,
      ast: $ast,
      cursor_index: $cursor_index,
      token: $token,
      prev_token: $prev_token,
      command: (command-at-position $pipeline $cursor_index),
      completion_types: $completion_types
    }
}

export def current-completion-context []: nothing -> record {
  completion-context (commandline) (commandline get-cursor)
}

