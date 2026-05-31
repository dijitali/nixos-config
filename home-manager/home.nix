{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home = {
    username = "ieuan";
    homeDirectory = "/home/ieuan";
  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # enable flakes
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  xdg.autostart.entries.signal-desktop = {
    name = "Signal Desktop";
    exec = "/run/current-system/sw/bin/signal-desktop";
    type = "Application";
  };

  programs = {
    # Let Home Manager install and manage itself.
    home-manager.enable = true;

    git = {
      enable = true;
      signing = {
        format = "ssh";
        key = "~/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
      settings = {
        user = {
          name = "Ieuan Jenkins";
          email = "hi@ieuan.net";
        };
        credential = {
          helper = "cache";
        };
        core = {
          excludesfile = "/home/ieuan/.gitignore";
          editor = "vim";
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
        gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
      };
    };

    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        code = "codium";
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

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".ssh/allowed_signers".text = ''
      hi@ieuan.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICd3qvLJCEGwvZLWl5dUXI/WAV9a7DDTYa+NlDA9Yjeo
    '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ieuan/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
    UV_PYTHON_DOWNLOADS = "never";
    UV_PYTHON = "/run/current-system/sw/bin/python3.14";
  };

}
