# Gost SOCKS5 proxy service with encrypted DNS
# Requires sops-nix for secrets management
{ config, pkgs, ... }:
{
  sops = {
    # [{"addr": string, "chain"?: string, "prefer"?: "ipv4" | "ipv6", "clientIp"?: string, "ttl"?: duration, "timeout"?: duration}]
    # https://gost.run/en/reference/configuration/file/#nameserver
    secrets."gost/nameservers" = { };

    templates."gost-config.json".content =
      # json
      ''
        {
          "services": [
            {
              "name": "socks-proxy",
              "addr": ":1080",
              "handler": {"type": "socks5"},
              "listener": {"type": "tcp"},
              "resolver": "socks-proxy"
            }
          ],
          "resolvers": [
            {
              "name": "socks-proxy",
              "nameservers": ${config.sops.placeholder."gost/nameservers"}
            }
          ]
        }
      '';
  };

  systemd.user.services.gost = {
    Unit = {
      Description = "SOCKS5 proxy with unfiltered DNS";
      After = [ "sops-nix.service" ];
      Requires = [ "sops-nix.service" ];
    };
    Service = {
      ExecStart = "${pkgs.gost}/bin/gost -C ${config.sops.templates."gost-config.json".path}";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
