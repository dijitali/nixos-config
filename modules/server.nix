# Baseline for headless cloud servers: SSH, firewall, networking, Tailscale and
# passwordless sudo for wheel. IPv4 comes from DHCP; on Hetzner Cloud the IPv6
# address is read from the metadata service at boot (`server.hetznerMetadataIPv6`),
# so no addresses are pinned in this repo.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.server;
in
{
  options.server = {
    hetznerMetadataIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Configure the server's public IPv6 address from the Hetzner Cloud
        metadata service at every boot. Hetzner assigns a /64 per server but
        does not announce it over RA/DHCPv6; the metadata service's
        network-config carries the address and gateway. Following it at boot
        means a changed primary IP needs no config change here.
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

    # Local stub resolver; tailscaled hands it the tailnet's MagicDNS domain as a
    # split-DNS route, so *.ts.net names resolve (e.g. Caddy upstreams on the
    # tailnet) without tailscaled rewriting /etc/resolv.conf.
    services.resolved.enable = true;

    systemd.network.networks."10-wan" = {
      # Hetzner Cloud x86 guests show up as ens*/enp*/eth0 depending on the
      # kernel and whether predictable names are on; match them all.
      matchConfig.Name = "en* eth*";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
    };

    # Reads the IPv6 address and gateway from Hetzner's metadata service (reached
    # over the DHCPv4 link) and adds them to 10-wan as a runtime drop-in under
    # /run, then has networkd reconfigure. Re-done every boot; if the metadata
    # service is unavailable, IPv4 still works and the unit retries.
    systemd.services.hetzner-metadata-ipv6 = lib.mkIf cfg.hetznerMetadataIPv6 {
      description = "Configure IPv6 from Hetzner Cloud metadata";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.curl
        pkgs.yq-go
        config.systemd.package
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 10;
      };
      script = ''
        set -euo pipefail
        config=$(curl -fsS --retry 5 --retry-connrefused --retry-delay 2 \
          http://169.254.169.254/hetzner/v1/metadata/network-config)
        subnet='[.config[] | select(.type == "physical") | .subnets[] | select(.ipv6 == true and .type == "static")][0]'
        address=$(printf '%s' "$config" | yq "$subnet.address" -)
        gateway=$(printf '%s' "$config" | yq "$subnet.gateway" -)
        if [ -z "$address" ] || [ "$address" = null ] || [ -z "$gateway" ] || [ "$gateway" = null ]; then
          echo "no static IPv6 subnet in Hetzner network-config" >&2
          exit 1
        fi
        mkdir -p /run/systemd/network/10-wan.network.d
        printf '[Network]\nAddress=%s\n\n[Route]\nGateway=%s\n' "$address" "$gateway" \
          > /run/systemd/network/10-wan.network.d/50-hetzner-ipv6.conf
        networkctl reload
        echo "configured $address via $gateway"
      '';
    };

    services.openssh = {
      enable = true;
      # Generated in OpenTofu and written by nixos-anywhere at install time, so
      # the host identity is stable across reboots (impermanent root) and
      # reinstalls. sshd generates it here if missing.
      hostKeys = [
        {
          path = "/nix/persist/secrets/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
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

    # Nix's GitHub token (see modules/nix.nix), written by nixos-anywhere at
    # install time from vps-config's OpenTofu. Root-only; used by auto-upgrade
    # to fetch the private site repos.
    environment.etc."nix/access-tokens.conf".source = "/nix/persist/secrets/nix-access-tokens";

    # Deploys push the system closure over SSH as the admin user, which needs
    # to be trusted by the Nix daemon to add paths to the store.
    nix.settings.trusted-users = [ "@wheel" ];

    services.tailscale = {
      enable = true;
      openFirewall = true;
      # Written at install time (nixos-anywhere extra files) from a single-use,
      # pre-authorised tailnet key created in vps-config's OpenTofu. Only used
      # until the node has state in /var/lib/tailscale; harmless after that.
      authKeyFile = "/nix/persist/secrets/tailscale-authkey";
      extraUpFlags = lib.optional (
        cfg.tailscaleTags != [ ]
      ) "--advertise-tags=${lib.concatStringsSep "," cfg.tailscaleTags}";
    };
  };
}
