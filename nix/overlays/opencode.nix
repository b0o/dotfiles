{
  inputs,
  final,
}: let
  inherit (final.stdenv.hostPlatform) system;
  unwrapped = inputs.opencode.packages.${system}.default;
in
  final.runCommand "opencode-wrapped" {
    nativeBuildInputs = [final.makeWrapper];
    meta = unwrapped.meta // {mainProgram = "opencode";};
  } ''
    mkdir -p $out/bin
    cat > $out/bin/opencode <<'WRAPPER'
    #!/usr/bin/env bash
    # Check if user passed --hostname or --port
    has_hostname=false
    has_port=false
    for arg in "$@"; do
      case "$arg" in
        --hostname|--hostname=*) has_hostname=true ;;
        --port|--port=*) has_port=true ;;
      esac
    done

    extra_args=()
    if [[ "$has_hostname" == false && "$has_port" == false ]]; then
      port="$(${final.python3}/bin/python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"
      extra_args+=(--hostname localhost --port "$port")
    fi

    exec ${unwrapped}/bin/opencode "''${extra_args[@]}" "$@"
    WRAPPER
    chmod +x $out/bin/opencode
  ''
