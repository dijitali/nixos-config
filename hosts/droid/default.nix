# Host: droid (Android / Termux via Nix-on-Droid)
#
# This is the Nix-on-Droid equivalent of a NixOS host. It uses its own module
# system (environment.packages / user.shell instead of
# environment.systemPackages / users.users), so it can't share the laptop's
# system modules — but the Home Manager config in ./home.nix mirrors the same
# shell/git preferences.
{ pkgs, ... }:

{
  # Packages available in the on-device environment. Keep this lean — it's a
  # phone, not the laptop — focused on terminal admin/dev.
  environment.packages = with pkgs; [
    git
    gnupg
    openssh
    helix
    fzf
    ripgrep
    jq
    curl
    wget
    tmux
    gh
    nixd
    nixfmt
  ];

  # Login shell for the Nix-on-Droid user.
  user.shell = "${pkgs.zsh}/bin/zsh";

  # Enable flakes + the new CLI so `nix-on-droid switch --flake` works
  # on-device.
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Per-user configuration via Home Manager.
  home-manager = {
    useGlobalPkgs = true;
    config = import ./home.nix;
  };

  # Read the Nix-on-Droid release notes before changing.
  system.stateVersion = "25.11";
}
