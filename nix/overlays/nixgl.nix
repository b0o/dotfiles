# NixGL overlay for non-NixOS systems with NVIDIA GPUs
#
# This overlay:
# 1. Pins the nvidia driver version to match the system's installed driver
# 2. Adds GBM_BACKENDS_PATH to the wrapper, which is required for Wayland/EGL apps
#
# NOTE: This works for apps running inside a compositor session (ghostty, waybar, etc.)
# but NOT for compositors themselves. Compositors need system nvidia libs for DRM/KMS
# operations, and the nix-built nvidia libs are incompatible with nvidia-open kernel module.
# Use system-installed compositor (e.g. /usr/bin/niri) instead.
#
# TODO: remove driver version pinning once https://github.com/nix-community/nixGL/pull/218 is merged
{inputs}: final: prev: let
  nvidiaVersion = "590.48.01";
  nvidiaHash = "sha256-ueL4BpN4FDHMh/TNKRCeEz3Oy1ClDWto1LO/LWlr1ok=";

  # Build nixgl with pinned driver version
  nixglBase = final.callPackage (inputs.nixGL.outPath + "/default.nix") {
    inherit nvidiaVersion nvidiaHash;
  };

  # The original nixGLNvidia wrapper doesn't set GBM_BACKENDS_PATH,
  # which is required for GBM/EGL to find the nvidia driver on Wayland.
  # We create patched wrappers that include this environment variable.
  patchNvidiaWrapper = wrapper: let
    wrapperName = wrapper.name;
    gbmPath = "${nixglBase.nvidiaLibsOnly}/lib/gbm";
  in
    final.writeShellScriptBin wrapperName ''
      export GBM_BACKENDS_PATH="${gbmPath}''${GBM_BACKENDS_PATH:+:$GBM_BACKENDS_PATH}"
      exec ${wrapper}/bin/${wrapperName} "$@"
    '';
in {
  nixgl =
    nixglBase
    // {
      # Override the nvidia wrappers with our patched versions
      nixGLNvidia = patchNvidiaWrapper nixglBase.nixGLNvidia;
      nixVulkanNvidia = patchNvidiaWrapper nixglBase.nixVulkanNvidia;
    };
}
