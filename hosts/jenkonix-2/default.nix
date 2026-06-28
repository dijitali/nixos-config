# Host: jenkonix-2 (Dell XPS 13 9310)
#
# This file wires together the hardware profile, the shared modules and the
# host-specific bits (hostname, disk encryption, state version). Everything
# reusable lives under ../../modules; only things genuinely unique to this
# machine belong here.
{ inputs, ... }:

{
  imports = [
    # Machine-generated hardware scan. Generate with `nixos-generate-config`
    # and copy the result here as ./hardware-configuration.nix, then `git add`
    # it so the flake can see it (untracked files are invisible to flakes).
    ./hardware-configuration.nix

    # Hardware quirks/optimisations for this exact laptop.
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310

    # Shared system modules.
    ../../modules/boot.nix
    ../../modules/networking.nix
    ../../modules/desktop.nix
    ../../modules/hardware.nix
    ../../modules/security.nix
    ../../modules/locale.nix
    ../../modules/packages.nix
    ../../modules/nix.nix
  ];

  networking.hostName = "jenkonix-2";

  # NOTE: the LUKS root device is defined in ./hardware-configuration.nix,
  # which nixos-generate-config keeps in sync with the actual disk UUID. Do
  # not duplicate it here.

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "25.11";
}
