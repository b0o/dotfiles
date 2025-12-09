# Build opentui from source specifically for opencode (b0o fork)
{
  lib,
  stdenv,
  stdenvNoCC,
  bun,
  nodejs,
  zig_0_14,
  cacert,
  fetchurl,
  src,
  bunDepsHash ? "sha256-tOFxVJ61kINEbj1CE2TfHBifsEOV/zLp0VnxkVw47ZQ=",
}: let
  version = "0.1.59-b0o";

  uucode = fetchurl {
    url = "https://github.com/jacobsandlund/uucode/archive/refs/tags/v0.1.0-zig-0.14.tar.gz";
    hash = "sha256-fzQ8vinib28zEml38cCPvdkHXDyuEBe1+Q/Rt765UpQ=";
  };
  # Hash from build.zig.zon
  uucodeZigHash = "uucode-0.1.0-ZZjBPpAFQABNCvd9cVPBg4I7233Ays-NWfWphPNqGbyE";

  bunDeps = stdenvNoCC.mkDerivation {
    pname = "opentui-bun-deps";
    inherit version src;
    nativeBuildInputs = [bun cacert];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = bunDepsHash;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile --ignore-scripts
    '';

    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/
      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    dontFixup = true;
  };
in
  stdenv.mkDerivation {
    pname = "opentui";
    inherit version src;

    nativeBuildInputs = [bun nodejs zig_0_14];

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR

      cp -r ${bunDeps}/node_modules .
      chmod -R u+w node_modules

      mkdir -p $HOME/.cache/zig/p/${uucodeZigHash}
      tar -xzf ${uucode} -C $HOME/.cache/zig/p/${uucodeZigHash} --strip-components=1

      patchShebangs node_modules/typescript/bin

      (cd packages/core && bun run build:native && bun run build:lib)
      (cd packages/solid && bun run build --ci)
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/@opentui

      cp -r packages/core/dist $out/lib/node_modules/@opentui/core

      for pkg in packages/core/node_modules/@opentui/core-*; do
        [ -d "$pkg" ] && cp -r "$pkg" $out/lib/node_modules/@opentui/
      done

      cp -r packages/solid/dist $out/lib/node_modules/@opentui/solid
    '';

    meta = {
      description = "OpenTUI - TypeScript library for building terminal user interfaces";
      homepage = "https://github.com/sst/opentui";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  }
