{lib}: let
  inherit (lib) optionalAttrs concatStringsSep filter;
in {
  # Helper to create a ZFS dataset with common properties
  # Optional owner/group/mode generate postMountHook for permissions
  mkDataset = {
    mountpoint,
    options ? {},
    postCreateHook ? null,
    postMountHook ? null,
    owner ? null,
    group ? null,
    mode ? null,
  }: let
    chownArg =
      if owner != null && group != null
      then "${toString owner}:${toString group}"
      else if owner != null
      then toString owner
      else if group != null
      then ":${toString group}"
      else null;

    chownCmd =
      if chownArg != null
      then "chown ${chownArg} /mnt${mountpoint}"
      else null;

    chmodCmd =
      if mode != null
      then "chmod ${mode} /mnt${mountpoint}"
      else null;

    permissionHook = concatStringsSep "\n" (filter (x: x != null) [chownCmd chmodCmd]);

    finalPostMountHook =
      if permissionHook != "" && postMountHook != null
      then permissionHook + "\n" + postMountHook
      else if permissionHook != ""
      then permissionHook
      else postMountHook;
  in
    {
      type = "zfs_fs";
      inherit mountpoint options;
    }
    // optionalAttrs (postCreateHook != null) {inherit postCreateHook;}
    // optionalAttrs (finalPostMountHook != null) {postMountHook = finalPostMountHook;};

  # Helper to set snapshot retention (all values explicit)
  snapshotDataset = {
    frequent,
    hourly,
    daily,
    weekly,
    monthly,
  }: {
    "com.sun:auto-snapshot" = "true";
    "com.sun:auto-snapshot:frequent" = toString frequent;
    "com.sun:auto-snapshot:hourly" = toString hourly;
    "com.sun:auto-snapshot:daily" = toString daily;
    "com.sun:auto-snapshot:weekly" = toString weekly;
    "com.sun:auto-snapshot:monthly" = toString monthly;
  };
}
