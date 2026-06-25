# System-level account for the ieuan user. The matching Home Manager
# configuration lives alongside this in ./home.nix and is wired up by
# lib/mkSystem.nix.
{ pkgs, ... }:

{
  users.users.ieuan = {
    isNormalUser = true;
    description = "Ieuan";
    extraGroups = [
      "networkmanager"
      "wheel"
      "scanner"
      "lp"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      kdePackages.kate
    ];
  };
}
