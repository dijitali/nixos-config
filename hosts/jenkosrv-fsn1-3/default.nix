# Host: jenkosrv-fsn1-3 (Hetzner Cloud cx23, Falkenstein)
#
# Headless web server, installed by nixos-anywhere from vps-config's OpenTofu
# (see vps-config/docs/nixos-migration.md). Everything reusable lives under
# ../../modules; only the disk layout and this machine's addresses belong here.
{
  inputs,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    # Hetzner Cloud runs KVM/QEMU guests: virtio drivers in the initrd.
    (modulesPath + "/profiles/qemu-guest.nix")

    inputs.disko.nixosModules.disko
    ./disk-config.nix

    ../../modules/server.nix
    ../../modules/impermanence.nix
    ../../modules/web/sites.nix
    ../../modules/locale.nix
    ../../modules/nix.nix
    ../../modules/vuln-scan
  ];

  networking.hostName = "jenkosrv-fsn1-3";

  # IPv4 from DHCP; IPv6 from the Hetzner metadata service at boot, so the
  # primary IPs created in vps-config are never pinned here.
  server.hetznerMetadataIPv6 = true;
  server.tailscaleTags = [
    "tag:personal"
    "tag:work"
  ];

  # Sites served by Caddy (modules/web/sites.nix): each is a flake input whose
  # `caddyConfig` output is its self-contained Caddy config.
  web.acmeEmail = "hi@ieuan.net";
  web.sites = {
    inherit (inputs)
      ieuan-net
      ieuan-co-uk
      jensys-uk
      net-diagnostics
      jnkns-uk
      ;
  };

  # Caddy 2.11.7 links golang.org/x/net v0.56.0, whose http2 server has
  # flow-control and HPACK advisories (GO-2026-6612/CVE-2026-78663 among them;
  # fixed in v0.60.0, the html ones in v0.62.0). Requiring the http2 package,
  # which Caddy imports anyway, raises the whole module through Go's minimum
  # version selection; it isn't a plugin. withPlugins' install check expects
  # every entry to be a module in `caddy build-info`, so it is told to look for
  # the x/net module at that version instead, which also proves the bump took.
  # The hash covers the Caddy version too (on a mismatch, nix prints the hash
  # it got; Renovate rewrites it with scripts/update-caddy-hash.sh). Drop all
  # of this once Caddy itself requires x/net v0.62.0.
  services.caddy.package =
    (pkgs.caddy.withPlugins {
      plugins = [ "golang.org/x/net/http2@v0.62.0" ];
      hash = "sha256-3Re2885iIMxiYfI/+DcR3XOzN9ZJszzlfwJINNvM0iM=";
    }).overrideAttrs
      (old: {
        installCheckPhase =
          builtins.replaceStrings [ "golang.org/x/net/http2@v0.62.0" ] [ "golang.org/x/net@v0.62.0" ]
            old.installCheckPhase;
      });

  # Weekly vulnerability report by email (modules/vuln-scan). The Fastmail app
  # password is written by vps-config's install script.
  security.vulnScan = {
    enable = true;
    mailTo = "hi@ieuan.net";
    smtp.passwordFile = "/nix/persist/secrets/smtp-password";
    goIgnore = {
      "GO-2026-5932" =
        "Deprecation notice for x/crypto/openpgp (linked by Caddy and Tailscale) with no fixed version; nothing to upgrade to.";
    };
  };

  # ieuan-net's built content is pushed, not built by Nix (it needs a GPG key
  # and Spotify credentials): `mise run deploy` rsyncs it into /var/www/public
  # as ieuan, keeping replaced files under /var/backups/ieuan-net.
  systemd.tmpfiles.rules = [
    "d /var/www/public 0755 ieuan users -"
    "d /var/backups/ieuan-net 0755 ieuan users -"
  ];

  # State that must survive the wipe-on-boot root, on the /persist volume (see
  # modules/impermanence.nix for the baseline list).
  environment.persistence."/persist".directories = [
    # ACME account and certificates; losing them each boot would hit Let's
    # Encrypt rate limits.
    {
      directory = "/var/lib/caddy";
      user = "caddy";
      group = "caddy";
      mode = "0700";
    }
    # What the last vulnerability report listed, so the next one can say
    # what's new and what's resolved; and vulnix's NVD cache (~200 MB, slow
    # to rebuild).
    "/var/lib/vuln-scan"
    "/var/cache/vuln-scan"
    # ieuan-net's pushed site content (site configs come from Nix).
    {
      directory = "/var/www";
      mode = "0755";
    }
    {
      directory = "/var/backups/ieuan-net";
      user = "ieuan";
      group = "users";
      mode = "0755";
    }
  ];

  # Shell history (histFile in users/ieuan/server.nix).
  environment.persistence."/persist".users.ieuan.directories = [
    {
      directory = ".local/state/zsh";
      mode = "0700";
    }
  ];

  # GRUB rather than systemd-boot: Hetzner Cloud boots x86 VMs via legacy BIOS
  # unless UEFI is requested, and this combination (plus the EF02 partition in
  # disk-config.nix) works in both modes. disko supplies `devices`.
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  # Headless: the menu is only reachable from Hetzner's web console, so keep a
  # short window for picking an older generation instead of the 5 s default.
  boot.loader.timeout = 1;

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "26.05";
}
