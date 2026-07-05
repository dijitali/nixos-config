# Boot loader and a themed graphical boot/unlock flow for the desktop
# machines. Kernel exploit mitigations (cmdline + sysctls) live in
# kernel-hardening.nix so server hosts can share them without pulling in
# systemd-boot/Plymouth.
{ pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        # Keep only the most recent generations in the boot menu (and on the
        # ESP), instead of every generation ever built. Pairs with the weekly
        # GC / auto-upgrade to stop the menu and EFI partition filling up.
        configurationLimit = 10;
        # Disable the boot-time command-line editor. The default lets anyone at
        # the keyboard edit the kernel cmdline (e.g. init=/bin/sh) to bypass
        # access controls, which undermines the hardening in
        # kernel-hardening.nix.
        editor = false;
        # Use the highest available console resolution for the menu/prompt.
        consoleMode = "max";
      };
      efi.canTouchEfiVariables = true;
      # Seconds the boot menu is shown before booting the default generation.
      # With splash enabled below, this keeps a brief window to pick an older
      # build; set to 0 to hide the menu entirely behind the splash.
      timeout = 5;
    };

    # Graphical boot splash that also themes the LUKS passphrase prompt.
    # Breeze matches the Plasma 6 / SDDM look for a consistent boot -> unlock
    # -> login flow.
    plymouth = {
      enable = true;
      theme = "breeze";
      themePackages = [ pkgs.kdePackages.breeze-plymouth ];
    };

    # Render the LUKS unlock under the systemd-based initrd so Plymouth can
    # draw the passphrase prompt graphically instead of the plain console text.
    initrd.systemd.enable = true;

    # Quiet, seamless boot to let the splash take over the screen.
    kernelParams = [
      "quiet"
      "splash"
    ];
    consoleLogLevel = 0;
    initrd.verbose = false;
  };
}
