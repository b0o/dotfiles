{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib)
    attrsets
    mkAfter
    mkDefault
    mkIf
    mkOption
    strings
    types
    ;

  zfsLib = import ../../lib/zfs.nix { inherit lib; };
  inherit (zfsLib) mkDataset snapshotDataset;

  cfg = config.custom;
in
{
  imports = [
    inputs.disko.nixosModules.disko
  ];

  options.custom = {
    disk = {
      id = mkOption {
        type = types.str;
        description = "Disk device path (by-id)";
        example = "/dev/disk/by-id/nvme-...";
      };
      swapSize = mkOption {
        type = types.str;
        default = "64G";
        description = "Size of swap partition";
      };
    };

    secrets = {
      directory = mkOption {
        type = types.str;
        default = "/etc/nixos/secrets";
        description = "Directory to store secrets (password files, etc.)";
      };
      filesToCreate = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Files to create in secrets directory during partitioning";
      };
    };

    zfs.extraDatasets = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional ZFS datasets for the rpool";
    };
  };

  config = {
    boot = {
      loader = {
        systemd-boot = {
          enable = true;
          configurationLimit = 20;
        };
        efi = {
          canTouchEfiVariables = false;
          efiSysMountPoint = "/boot";
        };
      };

      supportedFilesystems = [ "zfs" ];
      zfs.requestEncryptionCredentials = false;

      # On each boot, roll back to the initial state of the root dataset
      # (see below)
      initrd.postResumeCommands = mkAfter ''
        zfs rollback -r rpool/rootfs@blank
      '';
    };

    disko.devices = {
      disk.main = {
        type = "disk";
        device = cfg.disk.id;
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = cfg.disk.swapSize;
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
      };

      zpool.rpool = {
        type = "zpool";
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          dnodesize = "auto";
          mountpoint = "none";
          canmount = "off";
          "com.sun:auto-snapshot" = "false";
        };

        datasets = attrsets.recursiveUpdate {
          # Ephemeral root - rolled back on every boot
          rootfs = mkDataset {
            mountpoint = "/";
            options."com.sun:auto-snapshot" = "false";
            # Capture the initial state of the root dataset
            # so that we can roll back to it on each boot (see above)
            postCreateHook = "zfs snapshot rpool/rootfs@blank";
          };

          # Nix store - reproducible, no snapshots needed
          nix = mkDataset {
            mountpoint = "/nix";
            options = {
              atime = "off";
              "com.sun:auto-snapshot" = "false";
            };
          };

          # System state datasets
          ssh = mkDataset {
            mountpoint = "/etc/ssh";
            options = snapshotDataset {
              frequent = 4;
              hourly = 24;
              daily = 7;
              weekly = 4;
              monthly = 0;
            };
          };

          tailscale = mkDataset {
            mountpoint = "/var/lib/tailscale";
            mode = "700";
            options = snapshotDataset {
              frequent = 4;
              hourly = 24;
              daily = 7;
              weekly = 4;
              monthly = 0;
            };
          };

          bluetooth = mkIf config.hardware.bluetooth.enable (mkDataset {
            mountpoint = "/var/lib/bluetooth";
            options = snapshotDataset {
              frequent = 4;
              hourly = 24;
              daily = 7;
              weekly = 4;
              monthly = 0;
            };
          });

          nixos = mkDataset {
            mountpoint = "/var/lib/nixos";
            options = snapshotDataset {
              frequent = 4;
              hourly = 24;
              daily = 7;
              weekly = 4;
              monthly = 0;
            };
          };

          log = mkDataset {
            mountpoint = "/var/log";
            options = snapshotDataset {
              frequent = 0;
              hourly = 0;
              daily = 7;
              weekly = 4;
              monthly = 3;
            };
            postCreateHook = "zfs snapshot rpool/log@clean";
          };

          secrets = mkDataset {
            mountpoint = cfg.secrets.directory;
            mode = "700";
            options = snapshotDataset {
              frequent = 4;
              hourly = 24;
              daily = 7;
              weekly = 4;
              monthly = 0;
            };
            postMountHook = strings.concatStringsSep "\n" (
              map (path: ''
                if [ ! -f /mnt${path} ]; then
                  mkpasswd changeme >/mnt${path}
                  chmod 600 /mnt${path}
                fi
              '') cfg.secrets.filesToCreate
            );
          };

          home = mkDataset {
            mountpoint = "/home";
            # Configure snapshots on sub-datasets inside of home
            options."com.sun:auto-snapshot" = "false";
          };
        } cfg.zfs.extraDatasets;
      };
    };

    fileSystems.${cfg.secrets.directory}.neededForBoot = true;

    networking.networkmanager.enable = mkDefault true;

    time.timeZone = mkDefault "America/Los_Angeles";
    i18n.defaultLocale = mkDefault "en_US.UTF-8";

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nixpkgs.config.allowUnfree = true;

    environment.systemPackages = with pkgs; [
      vim
      git
      cryptsetup
      parted
    ];

    services.zfs = {
      autoSnapshot.enable = true;
      autoScrub.enable = true;
      trim.enable = true;
    };

    users.mutableUsers = false;

    system.stateVersion = "25.05";
  };
}
