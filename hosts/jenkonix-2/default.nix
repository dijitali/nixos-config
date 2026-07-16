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
    ../../modules/secure-boot.nix
    ../../modules/locale.nix
    ../../modules/packages.nix
    ../../modules/nix.nix
  ];

  networking.hostName = "jenkonix-2";

  # The root LUKS device (luks-c54ac17e...) is declared in
  # ./hardware-configuration.nix. Encrypted swap lives on a second LUKS
  # partition: nixos-generate-config emits the swapDevices entry pointing at
  # /dev/mapper/luks-58f3676b... but NOT the unlock entry for it, so it must be
  # declared here or the swap mapper never opens and the swap unit fails at
  # boot. (If a future hardware-configuration.nix regeneration starts emitting
  # this same entry, remove it here to avoid a duplicate definition.)
  #
  # Both volumes carry crypttab options to try TPM2 (PIN-gated, sealed against
  # the Secure Boot state) and then FIDO2 (YubiKey) before falling back to the
  # passphrase prompt. These are inert until matching keyslots are enrolled
  # with systemd-cryptenroll — see docs/secure-boot.md.
  boot.initrd.luks.devices =
    let
      tokenUnlock = [
        "tpm2-device=auto"
        "fido2-device=auto"
        # Cap the wait for an absent YubiKey (default 30s). Only hit on the
        # fallback path after a TPM2 unlock failure.
        "token-timeout=10s"
      ];
    in
    {
      # Root; .device comes from hardware-configuration.nix.
      "luks-c54ac17e-bd99-4425-b4f8-c0cc62285b61".crypttabExtraOpts = tokenUnlock;
      "luks-58f3676b-64b0-4165-88f1-366ef142fbcf" = {
        device = "/dev/disk/by-uuid/58f3676b-64b0-4165-88f1-366ef142fbcf";
        crypttabExtraOpts = tokenUnlock;
      };
    };

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "25.11";
}
