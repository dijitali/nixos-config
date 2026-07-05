# Host: webserver (Hetzner Cloud VPS serving https://www.ieuan.net/)
#
# Headless server: no desktop, no Home Manager, key-only SSH. The site
# content and Caddyfile are deployed from the dijitali/ieuan-net repo with
# `mise run deploy` / `mise run caddy:deploy`; this config provides the OS,
# the Caddy service and the directories those deploys land in (./caddy.nix).
{ pkgs, ... }:

{
  imports = [
    # Hand-written profile for Hetzner Cloud's stable virtual hardware; see
    # the notes in that file before regenerating with nixos-generate-config.
    ./hardware-configuration.nix

    ./caddy.nix

    # Shared system modules.
    ../../modules/kernel-hardening.nix
    ../../modules/security.nix
    ../../modules/ssh-server.nix
    ../../modules/locale.nix
    ../../modules/nix.nix
  ];

  networking.hostName = "webserver";

  # Hetzner Cloud x86 VMs boot via BIOS from the first virtio disk, so GRUB
  # goes in the MBR rather than systemd-boot on an ESP (no UEFI here).
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  networking = {
    # IPv4 comes from Hetzner's DHCP.
    useDHCP = true;

    # IPv6: Hetzner Cloud assigns a /64 but does not offer SLAAC/DHCPv6, so
    # the address must be configured statically with the link-local gateway
    # fe80::1. Fill in the address from the Cloud Console and uncomment:
    #
    # interfaces.enp1s0.ipv6.addresses = [
    #   {
    #     address = "2a01:4f8:XXXX:XXXX::1";
    #     prefixLength = 64;
    #   }
    # ];
    # defaultGateway6 = {
    #   address = "fe80::1";
    #   interface = "enp1s0";
    # };

    firewall.enable = true;
    nftables.enable = true;
  };

  # Minimal admin/deploy toolbox. rsync must be present server-side for the
  # site deploy (scripts/deploy.sh in dijitali/ieuan-net) to work.
  environment.systemPackages = with pkgs; [
    git
    htop
    rsync
    vim
  ];

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "26.05";
}
