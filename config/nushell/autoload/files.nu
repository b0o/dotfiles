# Smart & pretty file and directory lister using eza and bat
export def l [
  --levels (-L): int = 1  # Levels of depth to display (for directories)
  target: path = "."     # Target file or directory to list
] {
  if not ($target | path exists) {
    error make -u {msg: $"Target does not exist: ($target)"}
  }
  let expanded = ($target | path expand)

  def default-viewer [
    --text (-t)  # Use text viewer
    file: string
  ] {
    let text = $text or (
      if (
        (which isutf8 | is-not-empty) and
        (isutf8 $file | complete).exit_code == 0) {
        true
      } else {
        false
      }
    )
    if ($text) {
      if (which bat | is-not-empty) {
        ^bat -- $file
      } else {
        ^cat -- $file
      }
    } else {
      if (which file | is-not-empty) {
        ^file -- $file
      }
      if (which identify | is-not-empty) {
        ^identify -- $file
      }
    }
  }

  def exif-viewer [
    file: path
  ] {
    if (which exiftool | is-not-empty) {
      ^exiftool $file
    }
  }

  match ($expanded | path type) {
    "dir" => {
      ^eza -algF --git --group-directories-first -TL $levels -- $expanded
    }
    "file" => {
      let mime_type = if (which xdg-mime | is-not-empty) {
        ^xdg-mime query filetype $expanded | str trim
      } else {
        "text/plain"
      } | split row '/'

      let type = ($mime_type | get 0)
      let subtype = ($mime_type | get 1)

      ^exa -algF --git -T -- $expanded
      match $type {
        "text" => {
          default-viewer --text $expanded
        }
        "image" => {
          exif-viewer $expanded
          if (which sips | is-not-empty) {
            ^sips -g pixelWidth -g pixelHeight -- $expanded
          } else {
            default-viewer $expanded
          }
        }
        "video" => {
          exif-viewer $expanded
          if (which ffprobe | is-not-empty) {
            ^ffprobe -hide_banner -loglevel error -- $expanded
          } else {
            default-viewer $expanded
          }
        }
        "application" => {
          if (
            ($expanded | path parse | get stem | str ends-with ".tar") or
            (($expanded | path parse | get extension) == "tar")
            and (which tar | is-not-empty)
          ) {
            print "Archive Listing:"
            ^tar -tvf $expanded
          } else if ($subtype == "zip" and (which unzip | is-not-empty)) {
            print "Archive Listing:"
            ^unzip -l $expanded
          } else if ($subtype == "x-7z-compressed" and (which 7z | is-not-empty)) {
            print "Archive Listing:"
            ^7z l $expanded
          } else if ($subtype == "pdf") {
            exif-viewer $expanded
            if (which pdfinfo | is-not-empty) {
              ^pdfinfo $expanded
            }
            default-viewer $expanded
          } else {
            default-viewer $expanded
          }
        }
      }
    }
  }
}

# mkdir and cd
export def --env mcd [
  ...args: string
] {
  let dir = ($args | path join)
  mkdir $dir
  cd $dir
}

alias l1 = l -L 1
alias l2 = l -L 2
alias l3 = l -L 3
alias l4 = l -L 4
alias l5 = l -L 5
alias l6 = l -L 6
alias l7 = l -L 7
alias l8 = l -L 8
alias l9 = l -L 9

alias cx = chmod +x
alias tf = tail -f
alias cat = bat
alias duh = du -h
alias dfh = df -h
alias mcdt = mcd /tmp
