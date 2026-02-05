# Comark (Comma Bookmark) for Nushell
# Shell bookmark manager and file search utility for quick navigation and file management

export use core.nu *
export use fzf.nu *

export def "comark generate-autoload" [] {
  [
    "use comark *\n"
    ...(l, | each { |row|
      $"# cd ($row.target)\nexport alias ,($row.name) = cd, ($row.name)"
    })
  ] | str join "\n"
}

export def "comark generate-autoload-hash" [] {
  try {
    glob $"(comark-dir)/*"
      | par-each { $in ++ ":" ++ ($in | path expand) }
      | sort
      | str join "\n"
      | hash md5
  } catch {
    ""
  }
}
