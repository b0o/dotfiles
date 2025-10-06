{
  # config,
  # pkgs,
  # lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../common.nix
  ];

  networking.hostName = "boonix";
  networking.hostId = "34725e80219de9db";

  # Your user
  users.users.boo = {
    isNormalUser = true;
    home = "/home/boo";
    uid = 1000;
    extraGroups = ["wheel" "networkmanager" "video" "audio"];
    initialPassword = "changeme"; # Change on first login!
  };

  # ZFS home dataset (will be mounted automatically via ZFS properties)
  # We'll set this up during install

  # Shared swap
  swapDevices = [
    {device = "/dev/disk/by-uuid/fe49887f-d9e9-413f-9088-8fcdd35bde28";}
  ];
}
