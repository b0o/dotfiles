export def "commands internal" []: nothing -> table {
    scope commands
      | where {|it| not $it.is_sub}
      | update description {|it| [$it.description, $it.search_terms] | str join " "}
      | select name description
}

export def "commands external" []: nothing -> table {
    $env.PATH
      | each --flatten {|it | try { ls --threads $it } }
      | par-each {|it |
          if ($it.type == symlink) {
            $it | update name ($it.name | path expand) | update type file
          } else {
            $it
          }
          | update name {|it| $it.name | path basename }
          | insert description ""
          # TODO: this info is nice to have, but this is too slow. Need to cache.
          # could use tldr instead or in addition? tldr would show usage
          # | insert description (carapace $in.name export | from json | default {Short: ""} | get Short | default "")
      }
      | where type == file
      | select name description
}

export def "commands aliases" [] : nothing -> table {
      scope aliases
        | select name description
}

export def "subcommands internal" [command: string]: nothing -> table {
  scope commands
    | where is_sub and ($it.name | str starts-with $command)
    | update name {split words | last}
    | update description {|it| [$it.description, $it.search_terms] | str join " "}
    | select name description
}

export def "subcommands external" [command: string]: nothing -> table {
    let carapace_data = (
      carapace $command export
        | from json
        | get -o Commands
    )
    if ($carapace_data | is-empty) {
      return null
    }

    $carapace_data
      | each --flatten {|it|
        [$it.Name]
        | (append $it.Aliases? | default [])
        | each {|name|
          {name: $name, description: ($it.Short? | default "")}
        }
      }
      | insert extra_description  ""
      | insert search_terms ""
}

export def "parameter-values external" [command: string, parameter: string]: nothing -> table {
  # TODO: check if carapace or other completion libraries offer this
  []
  | wrap name
  | insert description ""
}

export def "parameter-values internal" [command: string, parameter: string]: nothing -> table {
  try {
    scope commands
      | where name == $command
      | get signatures
      | first
      | values
      | first
      | where parameter_name == $parameter
      | first
      | get -o completion
      | default []
   } catch { |err|
      if ($err.msg | str starts-with "Row number too large") {
        null
      } else {
        error make $err
      }
   }
   | wrap name
   | insert description ""
}

# Splits the long and short versions of each flag into separate entries
# and formats them nicely for fuzzy finding
def format-flags [--short, --long]: table -> table {
  # If neither is passed, return all flags
  let both = not ($short or $long)

  let flags = $in
  let short_flags = (if $short or $both {
    $flags
      | compact short_name
      | update short_name {|it| $"-($it.short_name)" }
      | rename --column {short_name: name}
  } else {
    null
  })

  let long_flags = (if $long or $both {
    $flags
      | compact long_name
      | update long_name {|it| $"--($it.long_name)" }
      | rename --column {long_name: name}
  } else {
    null
  })

  ($short_flags | append $long_flags)
}

export def "flags external" [command: string, --short, --long]: nothing -> table {
  let carapace_data = (carapace $command export | from json)
  if ($carapace_data | is-empty) {
    return null
  }
  let flag_data = $carapace_data | get -o LocalFlags
  if ($flag_data | is-empty) {
    return null
  }

  let flags = $flag_data
    | rename --block {str downcase}
    | select -o shorthand longhand type usage
    | rename --column {shorthand: short_name, longhand: long_name, usage: description}
    | insert role {|it|
      if ($it.type == "string") {
        "named"
      } else {
        "switch"
      }
    }

  if ($flags | is-empty) {
    return null
  }
  match [$short, $long] {
    [true, false] => ($flags | format-flags --short)
    [false, true] => ($flags | format-flags --long)
    _ => ($flags | format-flags)
  }
}


export def "flags internal" [command: string, --short, --long]: nothing -> table {
  let flags = try {
    scope commands
      | where name == $command
      | get signatures
      | first
      | values
      | reduce { |it, acc | $acc | append $it }
      | where parameter_type in [switch named]
      | rename --column {parameter_name: long_name, short_flag: short_name, syntax_shape: type, parameter_type: role}
      | default "bool" type
      | select -o long_name short_name type description role
      | uniq
   } catch { |err|
      if ($err.msg | str starts-with "Row number too large") {
        null
      } else {
        error make $err
      }
   }

  if ($flags | is-empty) {
    return null
  }
  match [$short, $long] {
    [true, false] => ($flags | format-flags --short)
    [false, true] => ($flags | format-flags --long)
    _ => ($flags | format-flags)
  }
}

export def paths [prefix: path] {
  let prefix = ($prefix | str replace "~" $env.HOME)
  let args = (
    if ($prefix | str ends-with "/") {
      { dir: $prefix, pattern: "." }
    } else {
      { dir: ($prefix | path dirname | default --empty "."), pattern: ($prefix | path basename | default --empty ".") }
    }
  )
  (
    fd
    --print0
    --follow
    --hidden
    --exclude ".git/"
    --max-depth 5
    $args.pattern
    $args.dir
  )
  | split row (char -u '0000')
  | wrap name
  | insert description ""
}

export def vars [] {
  scope variables
    | select name type
    | rename --column { type: description }
}

export def describe-simple []: any -> string {
    $in | describe | str replace --regex "<.*" ""
}

export def value-description []: any -> string {
  let value = $in
  let type = $value | describe-simple
  match ($type) {
    "list" | "table" | "record" => $type
    "string" => $value
    _ => ($value | to json --serialize)
  }
}

export def env [] {
  $env
    | transpose name description
    | update name {|it| $"$env.($it.name)"}
    | update description {|it| $it.description | value-description }
}

export def attrs [var_name: string]: nothing -> table {
  # $env and $nu are special-cased because they don't appear in `scope variables`
  if ($var_name == "$env") {
    return (env | str replace "$env." "" name)
  }
  let values = (
    if ($var_name == "$nu") {
        [$nu]
    }  else {
      (
        scope variables
        | where name == $var_name
        | get value
      )
    }
  )
  if ($values | is-empty) {
    return null
  }

  let v = $values | first
  match ($v | describe-simple) {
    "record" => (
      $v
        | transpose name description
        | update description {|it| $it.description | value-description }
      )
    "table" => (
      $v
        | columns
        | wrap name
        | insert description ""
        | update description {|it| $it.description | value-description }
    )
    _ => null
  }
}

# Lists all supported types of completion candidates
export def types [] {
  {
      INTERNAL_COMMAND: "Internal commands and custom commands",
      EXTERNAL_COMMAND: "Binaries from `$env.PATH`",
      ALIAS: "Aliases",
      COMMAND: "`INTERNAL_COMMAND`, `EXTERNAL_COMMAND`, and `ALIAS` combined and deduplicated",
      SUBCOMMAND: "Subcommands of the current context's command",
      SHORT_FLAG: "Short form flags, like `-f`",
      LONG_FLAG: "Long form flags, like `--flag`",
      FLAG: "Any flag (long or short)",
      FLAG_ARG: "Valid values for a flag that takes an argument: `table --theme FLAG_ARG`",
      PATH: "Filesystem paths",
      ENV: "Environment variables",
      VAR: "Nushell variables in the current scope",
      ATTR: "Attributes of a variable",
  } | transpose name description
}

export def for-context [context?: record] {
  let context = if ($context | is-not-empty) { $context } else { $in }
  let command_type = $context.command? | default { type: null } | get type
  for types in $context.completion_types {
    let result = ($types | reduce --fold null {|type, acc|
      let candidates = match $type {
        "INTERNAL_COMMAND" => (commands internal)
        "EXTERNAL_COMMAND" => (commands external)
        "ALIAS" => (commands aliases)
        "COMMAND" =>  {
          (commands internal | insert type "INTERNAL_COMMAND")
            | append (commands external | insert type "EXTERNAL_COMMAND")
            | append (commands aliases | insert type "ALIAS")
            | uniq-by name
        }
        "SUBCOMMAND" => {
          match $command_type {
            "internal" => (subcommands internal $context.command.name)
            "external" => (subcommands external $context.command.name)
            null => null
          }
        }
        "SHORT_FLAG" => {
          match $command_type {
            "internal" => (flags internal --short $context.command.name)
            "external" => (flags external --short $context.command.name)
            null => null
          }
        }
        "LONG_FLAG" => {
          match $command_type {
            "internal" => (flags internal --long $context.command.name)
            "external" => (flags external --long $context.command.name)
            null => null
          }
        }
        "FLAG" => {
          let flags = match $command_type {
            "internal" => (flags internal $context.command.name)
            "external" => (flags external $context.command.name)
            null => null
          }
          if ($flags | is-empty) {
            return null
          }
          $flags | upsert type {|$it| if ($it.name | str starts-with "--") { "LONG_FLAG" } else { "SHORT_FLAG" }}
        }
        "FLAG_ARG" => {
          let flag_name = ($context.prev_token? | default {content: ""} | get content | str trim --left --char '-')
          match $command_type {
            "internal" => (parameter-values internal $context.command.name $flag_name)
            "external" => (parameter-values external $context.command.name $flag_name)
            null => null
          }
        }
        "PATH" => (paths ($context.token? | default {content: "."} | get content))
        "ENV" => (env)
        "VAR" => (vars)
        "ATTR" => (attrs ($context.prev_token? | default {content: ""} | get content))
        _ => (error make {msg: $"Unknown completion candidate type: ($type)"})
      }
      if ($candidates | is-not-empty) {
        $acc | append (
          $candidates | upsert type {|it| if ($it.type? | is-empty) { $type } else { $it.type }}
        )
      } else {
        $acc
      }
    })
    if ($result | is-not-empty) {
      return $result
    }
  }
}
