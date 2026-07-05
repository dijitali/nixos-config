# Caddy for www.ieuan.net.
#
# Split of responsibilities with the dijitali/ieuan-net repo:
#   * this module: the caddy binary (with the transform-encoder log plugin),
#     the systemd service, the firewall openings and the directories the
#     deploys land in;
#   * ieuan-net: the Caddyfile + snippets (installed into
#     /etc/caddy/sites-enabled/ by `mise run caddy:deploy`) and the built
#     site (rsynced into /var/www/public by `mise run deploy`).
#
# Keeping the Caddyfile out of the Nix store preserves that fast deploy loop:
# a config change is an rsync + `systemctl reload caddy`, not a rebuild.
{ pkgs, user, ... }:

let
  # Caddy with the transform-encoder plugin, which provides the `transform`
  # log format used for the Apache-style access log in the Caddyfile. Keep
  # the plugin pin and hash in sync with the devshell in
  # dijitali/ieuan-net/flake.nix. If a nixpkgs bump changes the Go
  # vendoring, the build fails with a hash mismatch — copy the correct hash
  # from the error message.
  caddyWithPlugins = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddyserver/transform-encoder@v0.0.0-20260423033309-ba4124974830" ];
    hash = "sha256-3j6l+jKIz8deLE7t3lhBL0QjZYG0zfMfnpqOcBf5Okw=";
  };
in
{
  services.caddy = {
    enable = true;
    package = caddyWithPlugins;

    # Runtime path, deliberately outside the Nix store (see header comment).
    # The relative `import ieuan-net.Caddyfile.snippets` in the Caddyfile
    # resolves against this directory, where caddy:deploy installs both
    # files. Until the first `mise run caddy:deploy`, the file is missing
    # and the caddy unit will fail to start — that's expected on a fresh
    # install.
    configFile = "/etc/caddy/sites-enabled/ieuan-net.Caddyfile";
    adapter = "caddyfile";

    # Build-time validation can't see a runtime /etc path; caddy:deploy
    # validates on the server before installing instead.
    checkConfig = false;
  };

  # The Caddyfile writes its access log under /run/access (tmpfs, so request
  # logs never persist across reboots; rotation keeps 1 day). The caddy unit
  # runs sandboxed (ProtectSystem), so allowlist the log dir explicitly in
  # case the sandboxing tightens in a future nixpkgs.
  systemd.services.caddy.serviceConfig.ReadWritePaths = [ "/run/access" ];

  systemd.tmpfiles.rules = [
    "d /run/access 0750 caddy caddy -"
    # Deploy target for caddy:deploy (root-installed configs).
    "d /etc/caddy/sites-enabled 0755 root root -"
    # Deploy target for the built site; owned by the deploy user so rsync
    # over SSH needs no elevation. Caddy only needs read access.
    "d /var/www 0755 ${user} users -"
    "d /var/www/public 0755 ${user} users -"
    # deploy.sh moves replaced/deleted files here (dated backup dirs).
    "d /var/backups/ieuan-net 0700 ${user} users -"
  ];

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    # HTTP/3 (QUIC).
    allowedUDPPorts = [ 443 ];
  };

  # TODO: webstats.ieuan.net reverse-proxies to localhost:8080; whatever
  # serves the stats there is not yet managed declaratively. Add it as a
  # systemd service here when ready.
}
