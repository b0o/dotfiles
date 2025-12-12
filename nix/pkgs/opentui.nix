# Build opentui from source specifically for opencode (b0o fork)
{
  lib,
  stdenv,
  bun,
  nodejs,
  zig_0_14,
  llvmPackages,
  cacert,
  src,
  outputHash ? "sha256-XzjPjvLnGUDU2Q+eyVYF5vIxBHiXxRDAt6bCRc5w1x0=",
}: let
  version = "0.1.59-b0o";
in
  stdenv.mkDerivation {
    pname = "opentui";
    inherit version src;
    nativeBuildInputs = [bun cacert nodejs zig_0_14 llvmPackages.bintools];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    inherit outputHash;

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR
      export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
      bun install --frozen-lockfile

      patchShebangs node_modules/typescript/bin

      (cd packages/core && bun run build)
      (cd packages/solid && bun run build)
    '';

    installPhase = ''
      echo "$out" > ./outdir
      mkdir -p $out/lib/node_modules/@opentui

      cp -r packages/core/dist $out/lib/node_modules/@opentui/core
      cp -r packages/solid/dist $out/lib/node_modules/@opentui/solid
      cp -r node_modules/solid-js $out/lib/node_modules/solid-js
      cp -r node_modules/yoga-layout $out/lib/node_modules/yoga-layout

      # The zig build process puts the core-{platform}-{arch} into the node_modules/@opentui/ directory
      # (these are not from NPM). We need to copy them over.
      for pkg in packages/core/node_modules/@opentui/core-*; do
        [ -d "$pkg" ] && cp -r "$pkg" $out/lib/node_modules/@opentui/
      done

      # Strip debug info from native libraries to ensure reproducibility
      # (Zig embeds non-deterministic cache paths in debug sections)
      # Use llvm-strip which can handle cross-compiled binaries (darwin, windows, arm64)
      find $out -type f \( -name "*.so" -o -name "*.dylib" -o -name "*.dll" \) \
        -exec llvm-strip --strip-debug {} \;

      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    meta = {
      description = "OpenTUI - TypeScript library for building terminal user interfaces";
      homepage = "https://github.com/sst/opentui";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  }
