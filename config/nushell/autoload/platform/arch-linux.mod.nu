def complete-pacman-installed-package [spans: list<string>] {
  use nushell/completion.nu carapace-complete
  carapace-complete --no-args $spans pacman '-Q'
}

# Like pacman -Ql but only show executable files
@complete complete-pacman-installed-package
export def pqlx [
  --all (-a)  # Show all executable files, including those not in PATH
  ...pkgs: string
] {
  def is-in-path [file: string] {
    for p in ($env.PATH | split row ":") {
      if ($file | str starts-with $p) {
        return true
      }
    }
    false
  }
  pacman -Ql ...$pkgs
    | lines
    | par-each { |entry|
        let item = $entry | split column -n 2 ' ' package file | first
        let target = $item.file | path expand
        if ($target | path type) != "file" {
          return null
        }
        let ls = ls -l $target | first
        let executable = ($ls.mode | str contains "x")
        let in_path = ($all or (is-in-path $item.file))
        if not (($ls.type == "file") and $executable and $in_path) {
          return null
        }
        $item
      }
    | sort-by package file
}
