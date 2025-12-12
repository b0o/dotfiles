# Build opentui-spinner from source against our opentui fork
{
  lib,
  stdenv,
  bun,
  cacert,
  src,
  opentui-b0o,
  outputHash ? "sha256-Qbe7dhHSHq7JIlc32ptPlrBprEVq60k08IJ1dV6S9EY=",
}: let
  version = "0.0.6-b0o";
in
  stdenv.mkDerivation {
    pname = "opentui-spinner";
    inherit version src;
    nativeBuildInputs = [bun cacert];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    inherit outputHash;

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile

      patchShebangs node_modules/.bin

      # Replace @opentui peer dependencies with our fork
      rm -rf node_modules/@opentui
      mkdir -p node_modules/@opentui
      for pkg in ${opentui-b0o}/lib/node_modules/@opentui/*; do
        cp -r "$pkg" "node_modules/@opentui/$(basename "$pkg")"
      done
      chmod -R u+w node_modules/@opentui

      # Also need solid-js from opentui
      rm -rf node_modules/solid-js
      cp -r ${opentui-b0o}/lib/node_modules/solid-js node_modules/solid-js
      chmod -R u+w node_modules/solid-js

      bun node_modules/tsdown/dist/run.mjs
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/opentui-spinner

      cp -r dist $out/lib/node_modules/opentui-spinner/
      cp package.json $out/lib/node_modules/opentui-spinner/

      # Copy cli-spinners dependency
      mkdir -p $out/lib/node_modules
      cp -r node_modules/cli-spinners $out/lib/node_modules/

      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    meta = {
      description = "A small & opinionated spinner library for OpenTUI";
      homepage = "https://github.com/msmps/opentui-spinner";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  }
