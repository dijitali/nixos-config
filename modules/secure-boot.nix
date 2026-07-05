# UEFI Secure Boot via lanzaboote: signs the systemd-boot bootloader and
# kernel+initrd (as unified kernel images) with our own keys on every rebuild,
# so the firmware refuses to boot anything tampered with on the unencrypted
# ESP. Setup is NOT automatic — keys must exist in /var/lib/sbctl before this
# module is enabled or the bootloader install step fails at rebuild time.
# Full setup and usage instructions: docs/secure-boot.md.
{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  # Lanzaboote replaces the systemd-boot module (it installs and signs
  # systemd-boot itself). The systemd-boot options in modules/boot.nix are
  # still honoured: lanzaboote reads editor, consoleMode, configurationLimit
  # and boot.loader.timeout for its loader configuration.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    # Secure Boot keys as created by `sbctl create-keys`.
    pkiBundle = "/var/lib/sbctl";
  };

  # Key creation/enrollment and Secure Boot troubleshooting.
  environment.systemPackages = [ pkgs.sbctl ];
}
