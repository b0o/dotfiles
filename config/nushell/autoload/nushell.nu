# Update xtras mod.nu file to import all xtras submodules
def update-xtras-module [] {
  let xtras_dir = ($nu.default-config-dir | path join "autoload" "xtras")
  let xtras_mod = ($xtras_dir | path join "mod.nu")
  mkdir $xtras_dir
  if ($xtras_mod | path exists) {
    rm $xtras_mod
  }
  [
    (
      ls ...(glob $"($xtras_dir)/*.nu")
      | where type == file
      | get name
      | path relative-to ($xtras_dir | path expand)
      | where { $in != "mod.nu" and $in != "index.nu" }
      | each { |f| $"export use ($f)"}
      | str join "\n"
    )
    (if ($xtras_dir | path join "index.nu" | path exists) {
      "export use index.nu *"
    })
  ] | compact | str join "\n" | save -a $xtras_mod
}

# Save a custom command to the autoload directory
# Useful to persist interactively created commands
def save-command [
  name: string,      # Name of the custom command
  dest?: string      # Destination file name (without extension) (default: _($name))
  --append(-a)       # Append to existing file without confirmation
  --desc(-d): string # Description of the function
  --xtras(-x)        # Save to xtras module
  --export(-e)       # Export the command
] {
  let source = view source $name
  let dest = ($dest | default $name)
  let path = ($nu.default-config-dir | path join "autoload" (if $xtras { "xtras" } else { null }) $"($dest).nu")
  if ($path | path exists) {
    match (
      if ($append) {
        "a"
      } else {
        input $"Path ($path) exists: [a]ppend, [r]eplace, [C]ancel? " | str trim | str downcase | default -e "c"
      }
    ) {
      "a" => {
        print "Appending to ($path)"
      }
      "r" => {
        print "Replacing ($path)"
        rm --interactive $path
        if ($path | path exists) {
          error make {msg: $"Failed to remove ($path)"}
        }
      }
      _ => {
        print "Cancelled"
        return
      }
    }

  }

  if ($export and $xtras and $name == $dest) {
    error make {msg: "Command and module name cannot be the same"}
  }

  print $"Saving ($name) to ($path)"
  ([
      (if ($path | path exists) { open $path })
      (if ($desc | is-not-empty) { $desc | split row "\n" | each {|l| $"# ($l)"} | str join "\n" })
      (if $export { $"export ($source)" } else { $source })
    ]
    | compact
    | str join "\n"
    | str replace -ram '\s+$' "\n"
    | str trim
    | save -f $path
  )

  if $xtras {
    update-xtras-module
  }
}

# Like save-command, but saves to xtras module
# If submod is not specified or is "index", saves to xtras/index.nu,
# which will be used like `use xtras/index.nu *`, so that all exports
# are available directly in the `xtras` module scope.
def save-xtra [
  name: string              # Name of the custom command
  submod?: string = "index" # Submodule name (default: index)
  --append(-a) = true       # Append to existing file without confirmation (default: true)
  --desc(-d): string        # Description of the function
  --export(-e) = true       # Export the command (default: true)
] {
  save-command --desc=$desc --xtras --export=$export --append=$append $name $submod
}

# Convert bash-style command to nushell syntax
# Handles line continuations (\) and wraps multi-line commands in parens
# Primary use-case: pasting curl commands from browser devtools
def sh2nu []: string -> string {
  let result = (
    $in
    | str replace -ra '\\\r?\n' "\n"  # Remove backslash continuations
    | str trim
  )
  if ($result | str contains "\n") {
    $"\(($result)\)"                  # Wrap in parens for multi-line
  } else {
    $result
  }
}

def xsh2nu [] {
  xco | sh2nu | xc
}
