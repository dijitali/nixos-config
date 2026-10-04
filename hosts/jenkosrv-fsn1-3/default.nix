# Host: jenkosrv-fsn1-3 (Hetzner Cloud cx23, Falkenstein)
#
# Headless web server, installed by nixos-anywhere from vps-config's OpenTofu
# (see vps-config/docs/nixos-migration.md). Everything reusable lives under
# ../../modules; only the disk layout and this machine's addresses belong here.
{ inputs, modulesPath, ... }:

{
  imports = [
    # Hetzner Cloud runs KVM/QEMU guests: virtio drivers in the initrd.
    (modulesPath + "/profiles/qemu-guest.nix")

    inputs.disko.nixosModules.disko
    ./disk-config.nix

    ../../modules/server.nix
    ../../modules/impermanence.nix
    ../../modules/web/ieuan-net.nix
    ../../modules/locale.nix
    ../../modules/nix.nix
  ];

  networking.hostName = "jenkosrv-fsn1-3";

  # IPv4 from DHCP; IPv6 from the Hetzner metadata service at boot, so the
  # primary IPs created in vps-config are never pinned here.
  server.hetznerMetadataIPv6 = true;
  server.tailscaleTags = [
    "tag:personal"
    "tag:work"
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
    # Site content and dated backups, rsynced by ieuan-net's deploy.sh.
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
