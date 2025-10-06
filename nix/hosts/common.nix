{
  # config,
  pkgs,
  # lib,
  ...
}: {
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot/efi";
    };

    supportedFilesystems = ["zfs"];
    zfs.requestEncryptionCredentials = true;
  };

  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages (keep minimal - use your flakey-profile for user stuff)
  environment.systemPackages = with pkgs; [
    vim
    git
    cryptsetup
    parted
  ];

  system.stateVersion = "25.05";
}
