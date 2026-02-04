{
  inputs,
  pkgs,
  lib,
  ...
}:
# Build zellij from source using the fenix Rust toolchain
# Based on the original flake.nix from the zellij repo
let
  # Using misaelaguayo's TerminalPassthrough fork:
  # https://github.com/misaelaguayo/zellij
  # TODO: remove once upstreamed
  version = "unstable-2025-01-28";
  rev = "29f88bfa7c363cd9c5aa26febc5a0262cdf030fd";

  inherit (pkgs.stdenv.hostPlatform) system;
  fenixPkgs = inputs.fenix.packages.${system};
  channel = "1.92.0";
  toolchainHash = "sha256-sqSWJDUxc+zaz1nBWMAJKTAGBuGWP25GCftIOlCEAtA=";

  rustToolchain = fenixPkgs.combine [
    (fenixPkgs.toolchainOf {
      inherit channel;
      sha256 = toolchainHash;
    }).completeToolchain
    (fenixPkgs.targets.wasm32-wasip1.toolchainOf {
      inherit channel;
      sha256 = toolchainHash;
    }).rust-std
  ];

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
  rustPlatform.buildRustPackage rec {
    pname = "zellij";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "maround95";
      repo = "zellij";
      inherit rev;
      sha256 = "sha256-U9t2WB9io/jj5SLCocNTW12vYcmYEGgpSC5BuH5YbPA=";
    };

    cargoLock = {
      lockFile = "${src}/Cargo.lock";
      allowBuiltinFetchGit = true;
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.protobuf
      pkgs.pkg-config
      pkgs.perl # for openssl-sys
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
      pkgs.curl
      pkgs.openssl
    ];

    # Skip tests as they require additional setup
    doCheck = false;

    meta = with pkgs.lib; {
      description = "A terminal workspace with batteries included";
      homepage = "https://zellij.dev/";
      license = licenses.mit;
      platforms = platforms.unix;
    };
  }
