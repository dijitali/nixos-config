# System-wide programs and packages.
{ inputs, pkgs, ... }:

let
  # A pinned nixos-unstable snapshot, used only for packages we want to track
  # faster than the stable channel (see below). Kept local to this module so
  # the rest of the system stays on `pkgs` (stable).
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
{
  programs = {
    firefox.enable = true;
    # zsh is enabled here because it is a login shell (see users/ieuan).
    zsh.enable = true;
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "ieuan" ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.packageOverrides = pkgs: {
    xsaneGimp = pkgs.xsane.override { gimpSupport = true; };
  };

  environment.systemPackages = with pkgs; [
    cheese
    chromium
    pkgs-unstable.claude-code
    comaps
    diceware
    dig
    fzf
    gh
    ghostty
    gimp
    gnumake
    gnupg
    helix
    inkscape
    krita
    libreoffice
    macchina
    mozillavpn
    nixd
    nixfmt
    openssl
    opentofu
    organicmaps
    powershell
    pre-commit
    python314
    signal-desktop
    spotify
    tesseract
    usbutils
    uv
    vscodium
    yubikey-manager

    # KDE
    kdePackages.kcalc
    kdePackages.kcharselect
    kdePackages.kclock
    kdePackages.kcolorchooser
    kdePackages.kolourpaint
    kdePackages.ksystemlog
    kdePackages.sddm-kcm
    kdePackages.isoimagewriter
    kdePackages.partitionmanager
    kdiff3

    # Non-KDE graphical
    hardinfo2
    vlc
    wayland-utils
    wl-clipboard
  ];
}
