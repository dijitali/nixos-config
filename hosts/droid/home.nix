# Home Manager config for the Nix-on-Droid environment.
#
# Deliberately lighter than users/ieuan/home.nix: no desktop autostart, no
# YubiKey-based SSH commit signing (the hardware isn't available on the phone),
# no SSH control sockets. Just the shell/git setup that travels well.
{ config, pkgs, ... }:

{
  home.stateVersion = "25.11";

  programs = {
    home-manager.enable = true;

    git = {
      enable = true;
      settings = {
        user = {
          name = "Ieuan Jenkins";
          email = "hi@ieuan.net";
        };
        github = {
          user = "dijitali";
        };
        alias = {
          prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        };
        color = {
          ui = true;
        };
        init = {
          defaultBranch = "main";
        };
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      silent = true;
    };

    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        cz = "uv tool run --from commitizen cz";
      };
      history = {
        expireDuplicatesFirst = true;
        extended = true;
        ignoreAllDups = true;
        ignoreSpace = true;
        share = true;
        size = 100000;
      };
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
