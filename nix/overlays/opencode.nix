{
  inputs,
  final,
}: let
  inherit (final.stdenv.hostPlatform) system;
  unwrapped = inputs.opencode.packages.${system}.default;
  wrapperScript =
    # ts
    ''
      #!/usr/bin/env bun
      import { spawn } from "bun";
      import { createServer } from "net";

      const getRandomPort = () =>
        new Promise((resolve) => {
          const srv = createServer();
          srv.listen(0, "127.0.0.1", () => {
            const port = srv.address().port;
            srv.close(() => resolve(port));
          });
        });

      // Commands that only support --port (no --hostname)
      const supportsPortOnly = new Set(["run"]);
      // Commands that don't support --port or --hostname
      const noPortSupport = new Set([
        "completion", "mcp", "attach", "debug", "auth", "agent",
        "upgrade", "uninstall", "models", "stats", "export",
        "import", "github", "pr", "session"
      ]);

      const args = process.argv.slice(2);

      // Find first positional argument (not a flag or flag value)
      let subcommand = null;
      let skipNext = false;
      for (const arg of args) {
        if (skipNext) { skipNext = false; continue; }
        if (arg.startsWith("-")) {
          // Flags that take a value (without =)
          if (["--log-level", "-m", "--model", "-s", "--session", "--prompt", "--agent"].includes(arg)) {
            skipNext = true;
          }
          continue;
        }
        subcommand = arg;
        break;
      }

      // Check if user already passed --hostname or --port
      const hasHostname = args.some(a => a === "--hostname" || a.startsWith("--hostname="));
      const hasPort = args.some(a => a === "--port" || a.startsWith("--port="));

      let extraArgs = [];

      if (!hasHostname && !hasPort && !noPortSupport.has(subcommand)) {
        // Default TUI, path, or a command that supports flags
        const port = await getRandomPort();

        if (supportsPortOnly.has(subcommand)) {
          extraArgs = ["--port", String(port)];
        } else {
          // Default TUI (null/path), serve, web, acp
          extraArgs = ["--hostname", "localhost", "--port", String(port)];
        }
      }

      const proc = spawn(["${unwrapped}/bin/opencode", ...extraArgs, ...args], {
        stdio: ["inherit", "inherit", "inherit"],
      });

      const code = await proc.exited;
      process.exit(code);
    '';
in
  final.runCommand "opencode-wrapped" {
    meta = unwrapped.meta // {mainProgram = "opencode";};
  }
  # sh
  ''
    mkdir -p $out/bin
    cat > $out/bin/opencode <<'WRAPPER'
    ${wrapperScript}
    WRAPPER
    chmod +x $out/bin/opencode
  ''
