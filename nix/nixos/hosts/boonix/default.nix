{
  config,
  lib,
  ...
}:
let
  username = "boo";
  uid = 1000;

  zfsLib = import ../../../lib/zfs.nix { inherit lib; };
  inherit (zfsLib) mkDataset snapshotDataset;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
  ];

  custom = {
    disk.id = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_4TB_S7KGNU0X522072A";

    secrets.filesToCreate = [
      "${config.custom.secrets.directory}/${username}.password"
    ];

    zfs.extraDatasets = {
      "home/${username}" = mkDataset {
        mountpoint = "/home/${username}";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/downloads" = mkDataset {
        mountpoint = "/home/${username}/downloads";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 2;
          monthly = 0;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/.cache" = mkDataset {
        mountpoint = "/home/${username}/.cache";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 2;
          weekly = 0;
          monthly = 0;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/.local" = mkDataset {
        mountpoint = "/home/${username}/.local";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 2;
          monthly = 0;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/git" = mkDataset {
        mountpoint = "/home/${username}/git";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 3;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/proj" = mkDataset {
        mountpoint = "/home/${username}/proj";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 12;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };

      "home/${username}/work" = mkDataset {
        mountpoint = "/home/${username}/work";
        options = snapshotDataset {
          frequent = 4;
          hourly = 24;
          daily = 7;
          weekly = 4;
          monthly = 24;
        };
        owner = uid;
        group = 100;
        mode = "700";
      };
    };
  };

  networking.hostName = "boonix";
  networking.hostId = "aab75ae6";

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  users.users.${username} = {
    inherit uid;
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
    hashedPasswordFile = "${config.custom.secrets.directory}/${username}.password";
  };
}
