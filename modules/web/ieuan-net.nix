# Caddy as a generic host for push-deployed sites.
#
# Site config is not managed here: each site's own repo installs
# <site>.Caddyfile into /etc/caddy/sites-enabled/ and its content under
# /var/www/, then reloads Caddy (ieuan-net: `mise run caddy:deploy` and
# `mise run deploy`; jensys-uk, net-diagnostics, jnkns.uk: ./deploy.sh). This
# module provides what those scripts assume exists. Both directories persist
# across reboots (see the host's environment.persistence).
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
    # a warning, so Caddy starts cleanly before the first deploy.
    #
    # - The admin endpoint stays at its localhost-only default: the unit's
    #   reload (`systemctl reload caddy`, used by every deploy script) goes
    #   through it.
    # - Only *.Caddyfile is imported: snippet files such as
    #   ieuan-net.Caddyfile.snippets are imported by their site file, and
    #   importing them twice is a config error.
    adapter = "caddyfile";
    configFile = pkgs.writeText "Caddyfile" ''
      {
        # ACME account email, for certificate expiry/problem notices.
        email hi@ieuan.net
      }
      import /etc/caddy/sites-enabled/*.Caddyfile
    '';
  };

  # The Caddy unit is sandboxed (ProtectSystem) with only dataDir writable; the
  # access log lives on tmpfs under /run/access, as on the Ubuntu server.
  systemd.services.caddy.serviceConfig.ReadWritePaths = [ "/run/access" ];

  # The deploy scripts run `caddy validate` (as the caddy user) on the server
  # before reloading, so the same binary (with plugins) must be on PATH, not
  # just inside the unit.
  environment.systemPackages = [ config.services.caddy.package ];

  systemd.tmpfiles.rules = [
    # Site content and the dated backups of replaced files, both written by
    # deploy.sh over rsync as ieuan.
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
  # /nix/persist/secrets/ieuan-net-deploy-key (nixos-anywhere extra files).
  # Scoped to the local root user: `localuser`, since `user` would match the
  # remote login, which is always `git` on GitHub. Interactive users' own keys
  # are unaffected. GitHub's host keys are pinned (https://api.github.com/meta).
  programs.ssh = {
    extraConfig = ''
      Match localuser root host github.com
        IdentityFile /nix/persist/secrets/ieuan-net-deploy-key
        IdentitiesOnly yes
    '';
    knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
  };
}
