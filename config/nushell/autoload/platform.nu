source (
  if $nu.os-info.name == "linux" {
    "platform/linux.nu"
  } else if $nu.os-info.name == "darwin" {
    "platform/darwin.nu"
  } else if $nu.os-info.name == "windows" {
    "platform/windows.nu"
  } else {
    null
  }
)
