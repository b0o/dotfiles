# Build opencode with compiled binary (b0o fork with b0o opentui)
{
  lib,
  stdenvNoCC,
  bun,
  nodejs,
  cacert,
  fetchurl,
  opentui-b0o,
  src,
  nodeModulesHash ? "sha256-uml5TBHZK8dU5szJsg+eGrMjrEIXAYkpTaO0fPCXi7I=",
  modelsDevHash ? "sha256-XII+bKMje8ITRtB1krvvRgYgQPmDXGnmM4wwh6pp7sQ=",
}: let
  version = "1.0.137-b0o";

  modelsDev = fetchurl {
    url = "https://models.dev/api.json";
    hash = modelsDevHash;
  };

  nodeModules = stdenvNoCC.mkDerivation {
    pname = "opencode-node-modules";
    inherit version src;
    nativeBuildInputs = [bun cacert];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = nodeModulesHash;

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile --ignore-scripts
    '';

    installPhase = ''
      mkdir -p $out
      cp -r node_modules packages $out/
      find $out -exec touch -h -d '@0' {} + 2>/dev/null || true
    '';

    dontFixup = true;
  };
in
  stdenvNoCC.mkDerivation {
    pname = "opencode";
    inherit version src;

    nativeBuildInputs = [bun nodejs];

    dontConfigure = true;

    buildPhase = ''
      export HOME=$TMPDIR

      cp -r ${nodeModules}/{node_modules,packages} .
      chmod -R u+w node_modules packages

      # Replace npm opentui with our fork
      rm -rf node_modules/@opentui
      cp -r ${opentui-b0o}/lib/node_modules/@opentui node_modules/
      chmod -R u+w node_modules/@opentui

      cd packages/opencode

      # Link workspace packages
      mkdir -p node_modules/@opencode-ai
      ln -sf $(pwd)/../../packages/script node_modules/@opencode-ai/script
      ln -sf $(pwd)/../../packages/sdk/js node_modules/@opencode-ai/sdk
      ln -sf $(pwd)/../../packages/plugin node_modules/@opencode-ai/plugin

      patchShebangs ../../node_modules

      # Remove baseline/musl variants - bun --compile downloads runtimes which fails in sandbox
      sed -i '/avx2: false/d; /abi: "musl"/d' ./script/build.ts

      export OPENCODE_VERSION="${version}"
      export OPENCODE_CHANNEL="stable"
      export MODELS_DEV_API_JSON="${modelsDev}"
      bun run ./script/build.ts --single --skip-install
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp dist/opencode-*/bin/opencode $out/bin/
    '';

    meta = {
      description = "AI coding agent built for the terminal";
      homepage = "https://github.com/sst/opencode";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
      mainProgram = "opencode";
    };
  }
