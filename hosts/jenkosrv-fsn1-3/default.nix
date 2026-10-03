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
    ../../modules/web/ieuan-net.nix
    ../../modules/locale.nix
    ../../modules/nix.nix
  ];

  networking.hostName = "jenkosrv-fsn1-3";

  # Filled in once OpenTofu has created the server's primary IPv6 (phase 2 of
  # the migration). Until then the host is IPv4-only.
  server.ipv6Address = null;
  server.tailscaleTags = [
    "tag:personal"
    "tag:work"
  ];

  # GRUB rather than systemd-boot: Hetzner Cloud boots x86 VMs via legacy BIOS
  # unless UEFI is requested, and this combination (plus the EF02 partition in
  # disk-config.nix) works in both modes. disko supplies `devices`.
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "26.05";
}
