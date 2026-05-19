# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    <home-manager/nixos>
    <nixos-hardware/dell/xps/13-9310>
  ];

  # ---------------------------------------------------------------------------
  # Boot & Kernel
  # ---------------------------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-58f3676b-64b0-4165-88f1-366ef142fbcf".device =
    "/dev/disk/by-uuid/58f3676b-64b0-4165-88f1-366ef142fbcf";

  boot.kernel.sysctl = {
    # Restrict kernel pointer access
    "kernel.kptr_restrict" = 2;
    # Restrict dmesg to root
    "kernel.dmesg_restrict" = 1;
    # Disable SysRq
    "kernel.sysrq" = 0;
    # Protect symlinks/hardlinks
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    # Disable IP forwarding (not a router)
    "net.ipv4.ip_forward" = 0;
    # SYN flood protection
    "net.ipv4.tcp_syncookies" = 1;
    # Ignore ICMP redirects
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };

  # ---------------------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------------------

  networking.hostName = "jenkonix-2";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.nftables.enable = true;

  services.tailscale.enable = true;

  # Printer/service discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # ---------------------------------------------------------------------------
  # Hardware
  # ---------------------------------------------------------------------------

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };
  services.blueman.enable = true;

  hardware.sane.enable = true;

  # ---------------------------------------------------------------------------
  # Locale & Time
  # ---------------------------------------------------------------------------

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # ---------------------------------------------------------------------------
  # Desktop
  # ---------------------------------------------------------------------------

  # X11 windowing system (also required for Wayland sessions under SDDM)
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "gb";
    variant = "";
  };

  console.keyMap = "uk";

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true;
  };

  # Printing
  services.printing.enable = true;

  # ---------------------------------------------------------------------------
  # Security
  # ---------------------------------------------------------------------------

  security.sudo.wheelNeedsPassword = true;

  services.pcscd.enable = true;

  programs.ssh = {
    startAgent = true;
    enableAskPassword = true;
  };

  environment.variables = {
    SSH_ASKPASS_REQUIRE = "prefer";
  };

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------

  users.users.ieuan = {
    isNormalUser = true;
    description = "Ieuan";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  # ---------------------------------------------------------------------------
  # Programs & Packages
  # ---------------------------------------------------------------------------

  programs.firefox.enable = true;
  programs.zsh.enable = true;
  programs.gnupg.agent.enable = true;

  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "ieuan" ];
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.packageOverrides = pkgs: {
    xsaneGimp = pkgs.xsane.override { gimpSupport = true; };
  };

  environment.systemPackages = with pkgs; [
    cheese
    chromium
    claude-code
    comaps
    diceware
    dig
    fzf
    ghostty
    gimp
    gnupg
    helix
    inkscape
    krita
    libreoffice
    macchina
    mozillavpn
    nixfmt
    openssl
    opentofu
    organicmaps
    powershell
    python314
    signal-desktop
    spotify
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

  # ---------------------------------------------------------------------------
  # Nix & System
  # ---------------------------------------------------------------------------

  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.autoUpgrade.enable = true;

  # This value determines the NixOS release from which the default settings
  # for stateful data were taken. Do not change without reading the docs.
  system.stateVersion = "25.11";
}
