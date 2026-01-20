export def only-env [
  keep: list
  block: closure
  --std
  --set: record = {}
] {
  let keep = [
    PWD
    ...(if $std {[
      TERM COLORTERM SHELL SHLVL USER HOME HOSTNAME PATH TMPDIR
      XDG_CONFIG_HOME XDG_DATA_HOME XDG_DATA_DIRS XDG_CACHE_HOME
      XDG_STATE_HOME XDG_RUNTIME_DIR LANG LC_ALL LOCALE_ARCHIVE
      NIX_PATH NIX_PROFILES NIX_SSL_CERT_FILE NIX_STORE
      TERMINFO_DIRS LIBEXEC_PATH
    ]} else { [] })
    ...$keep
  ]
  hide-env -i ...($env | reject -o ...$keep | columns)
  with-env $set $block
}

const path_like_vars = [
  PATH MANPATH INFOPATH XDG_DATA_DIRS XDG_CONFIG_DIRS
  LD_LIBRARY_PATH LIBRARY_PATH PKG_CONFIG_PATH TERMINFO_DIRS
  CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH NIX_PATH
]

def split-path []: string -> list<string> {
  split row ':' | compact --empty
}

def to-path-parts []: any -> list<string> {
  if ($in | describe -d | get type) == 'list' { $in } else { $in | split-path }
}

def get-existing [name: string]: nothing -> list<string> {
  if $name == 'PATH' {
    $env.PATH? | default []
  } else {
    $env | get -o $name | default '' | split-path
  }
}

def merge-path [
  name: string
  value: any
  --append
]: nothing -> any {
  let new_parts = $value | to-path-parts
  let existing = get-existing $name
  let merged = (
    if $append { [...$existing, ...$new_parts] } else { [...$new_parts, ...$existing] }
  ) | uniq
  if $name == 'PATH' { $merged } else { $merged | str join ':' }
}

export def --env smart-load-env [
  new_env: record
  --append   # append new values instead of prepending
  --default  # only set unset vars; path-like vars merge with lower precedence
] {
  $new_env
  | items {|name, value|
      # --default: skip already-set non-path vars (before evaluating closure)
      if $default and ($name in $env) and ($name not-in $path_like_vars) {
        return null
      }

      # Evaluate closure lazily (only if we're going to use the value)
      let value = if ($value | describe -d | get type) == 'closure' {
        do $value
      } else {
        $value
      }

      let value = if $name in $path_like_vars {
        merge-path $name $value --append=($append or $default)
      } else {
        $value
      }
      [$name $value]
    }
  | compact
  | into record
  | load-env
}
