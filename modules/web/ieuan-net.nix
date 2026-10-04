# Caddy, configured to serve the ieuan.net sites.
#
# The site config itself lives in the ieuan-net repo: `mise run caddy:deploy`
# installs ieuan-net.Caddyfile (and its snippets) into /etc/caddy/sites-enabled/
# and reloads Caddy, and `mise run deploy` rsyncs the built site into
# /var/www/public. This module provides everything those scripts assume exists.
{ config, pkgs, ... }:

{
  services.caddy = {
    enable = true;

    # Same plugin pin as ieuan-net/flake.nix: the access_log snippet's
    # `format transform` needs transform-encoder. Keep the pin in sync; the
    # hash differs from ieuan-net's because it also covers the Caddy version
    # (this flake's nixpkgs vs ieuan-net's). On a mismatch, nix prints the
    # hash it got; paste it here.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddyserver/transform-encoder@v0.0.0-20260423033309-ba4124974830" ];
      hash = "sha256-EACMG870NkglP9fQBQR4/IOWsT+uqId02Di6BfVFfo0=";
    };

    # Mirrors the Ubuntu server's top-level Caddyfile. The NixOS module installs
    # this as /etc/caddy/caddy_config and nothing else under /etc/caddy, so the
    # imported directory is ours to fill at runtime; an unmatched glob just logs
    # a warning, so Caddy starts cleanly before the first `caddy:deploy`.
    adapter = "caddyfile";
    configFile = pkgs.writeText "Caddyfile" ''
      {
        admin off
      }
      import /etc/caddy/sites-enabled/*
    '';
  };

  # The Caddy unit is sandboxed (ProtectSystem) with only dataDir writable; the
  # access log lives on tmpfs under /run/access, as on the Ubuntu server.
  systemd.services.caddy.serviceConfig.ReadWritePaths = [ "/run/access" ];

  # ieuan-net's deploy-caddy.sh runs `sudo caddy validate` on the server before
  # installing a new Caddyfile, so the same binary (with plugins) must be on
  # PATH, not just inside the unit.
  environment.systemPackages = [ config.services.caddy.package ];

  systemd.tmpfiles.rules = [
    # Where caddy:deploy installs the site Caddyfile + snippets (as root).
    "d /etc/caddy/sites-enabled 0755 root root -"
    # Site content and the dated backups of replaced files, both written by
    # deploy.sh over rsync as ieuan.
    "d /var/www 0755 root root -"
    "d /var/www/public 0755 ieuan users -"
    "d /var/backups/ieuan-net 0755 ieuan users -"
    # Access log directory for the access_log snippet.
    "d /run/access 0750 caddy caddy -"
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Root can fetch the private ieuan-net repo with a read-only deploy key that
  # vps-config's OpenTofu creates and installs at
  # /nix/persist/secrets/ieuan-net-deploy-key (nixos-anywhere extra files). Scoped to root so interactive users' own keys
  # are unaffected. GitHub's host keys are pinned (https://api.github.com/meta).
  programs.ssh = {
    extraConfig = ''
      Match user root host github.com
        IdentityFile /nix/persist/secrets/ieuan-net-deploy-key
        IdentitiesOnly yes
    '';
    knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
  };
}
