# Baseline for headless cloud servers: SSH, firewall, networking, Tailscale and
# passwordless sudo for wheel. Host-specific addresses are set through the
# `server.*` options below.
{
  config,
  lib,
  ...
}:

let
  cfg = config.server;
in
{
  options.server = {
    ipv6Address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2a01:4f8:c013:6981::1/64";
      description = ''
        Static public IPv6 address with prefix length. Hetzner Cloud hands out
        a /64 per server but does not announce it over RA/DHCPv6, so the first
        address has to be configured here. IPv4 always comes from DHCP.
      '';
    };

    tailscaleTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tag:personal" ];
      description = "ACL tags to advertise when joining the tailnet.";
    };
  };

  config = {
    # Only SSH is reachable on the public interface; services that need more
    # (e.g. the web server) open their own ports.
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ];
      };
      nftables.enable = true;
    };

    systemd.network.networks."10-wan" = {
      # Hetzner Cloud x86 guests show up as ens*/enp*/eth0 depending on the
      # kernel and whether predictable names are on; match them all.
      matchConfig.Name = "en* eth*";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
      address = lib.optional (cfg.ipv6Address != null) cfg.ipv6Address;
      # Hetzner's IPv6 gateway is the link-local fe80::1 on every server.
      routes = lib.optional (cfg.ipv6Address != null) { Gateway = "fe80::1"; };
    };

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Key-only SSH and no other way in, so wheel does not need a password for
    # sudo. This is what lets `nixos-rebuild --target-host … --use-remote-sudo`
    # and ieuan-net's `sudo systemctl reload caddy` run non-interactively.
    security.sudo = {
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };

    # Deploys push the system closure over SSH as the admin user, which needs
    # to be trusted by the Nix daemon to add paths to the store.
    nix.settings.trusted-users = [ "@wheel" ];

    services.tailscale = {
      enable = true;
      openFirewall = true;
      # Written at install time (nixos-anywhere extra files) from a single-use,
      # pre-authorised tailnet key created in vps-config's OpenTofu. tailscaled
      # only reads it on first start; it is harmless once the node is joined.
      authKeyFile = "/var/lib/tailscale/authkey";
      extraUpFlags = lib.optional (
        cfg.tailscaleTags != [ ]
      ) "--advertise-tags=${lib.concatStringsSep "," cfg.tailscaleTags}";
    };
  };
}
