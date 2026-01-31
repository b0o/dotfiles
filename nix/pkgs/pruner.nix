{pkgs, ...}: let
  version = "1.0.0-alpha.8";

  sources = {
    "x86_64-linux" = {
      url = "https://github.com/pruner-formatter/pruner/releases/download/v${version}/pruner-linux-amd64";
      hash = "sha256-ouz/O2NEwyc+LLRAC1btJdgD/e3cPxSDVXOYs6XWViw=";
    };
    "aarch64-linux" = {
      url = "https://github.com/pruner-formatter/pruner/releases/download/v${version}/pruner-linux-arm64";
      hash = "sha256-MH6/FCO859atHaFsnGajKXaGrazwkwyUnIr6d4AUlCo=";
    };
    "x86_64-darwin" = {
      url = "https://github.com/pruner-formatter/pruner/releases/download/v${version}/pruner-macos-amd64";
      hash = "sha256-Sc24qap9WcRsIPOBAzWLp1MXRJS6XXd4EOEx5zEy7GM=";
    };
    "aarch64-darwin" = {
      url = "https://github.com/pruner-formatter/pruner/releases/download/v${version}/pruner-macos-arm64";
      hash = "sha256-UpxxS5WwkxLaSrK3vc1qs22AwX9qBAtBXQw3K/4hiL4=";
    };
  };

  inherit (pkgs.stdenv.hostPlatform) system;
  source = sources.${system} or (throw "Unsupported platform: ${system}");
in
  pkgs.stdenv.mkDerivation {
    pname = "pruner";
    inherit version;

    src = pkgs.fetchurl {
      inherit (source) url hash;
    };

    dontUnpack = true;

    nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgs.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -Dm755 $src $out/bin/pruner

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "A TreeSitter-powered formatter orchestrator";
      homepage = "https://github.com/pruner-formatter/pruner";
      license = licenses.mit;
      platforms = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    };
  }
