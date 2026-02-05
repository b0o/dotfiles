# Get the comark directory path
export def dir [] {
  $env
  | get -o COMARK_DIR
  | default (
    $env
    | get -o XDG_CONFIG_HOME
    | default ($env.HOME | path join ".config")
    | path join "comark"
  )
}

# Get the path to the comark JSON database
export def db-path [] {
  (dir) | path join "comark.json"
}
