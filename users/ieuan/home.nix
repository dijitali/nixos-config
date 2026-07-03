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
    (pkgs.writeShellScriptBin "git-ssh-signing-key" ''
      serials=$(${pkgs.yubikey-manager}/bin/ykman list --serials 2>/dev/null)
      if echo "$serials" | grep -qx 25305658; then
        key=${config.home.homeDirectory}/.ssh/id_ed25519_sk_yka.pub
      elif echo "$serials" | grep -qx 25440569; then
        key=${config.home.homeDirectory}/.ssh/id_ed25519_sk_ykc.pub
      else
        key=${config.home.homeDirectory}/.ssh/id_ed25519.pub
      fi
      echo "key::$(cat "$key")"
    '')
  ];

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
        gpg.ssh.defaultKeyCommand = "git-ssh-signing-key";
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

    ssh = {
      enable = true;
      # Opt out of Home Manager's default "*" block so the one below is the
      # only wildcard config.
      enableDefaultConfig = false;
      settings = {
        "*" = {
          addKeysToAgent = "yes";
          serverAliveInterval = 60;
          controlMaster = "auto";
          controlPath = "~/.ssh/sockets/%r@%h:%p";
          controlPersist = "10m";
          identitiesOnly = true;
          identityFile = "~/.ssh/id_ed25519";
        };
        yubikey-a = {
          match = ''exec "ykman list --serials 2>/dev/null | grep -qx 25305658"'';
          identityFile = "~/.ssh/id_ed25519_sk_yka";
        };
        yubikey-c = {
          match = ''exec "ykman list --serials 2>/dev/null | grep -qx 25440569"'';
          identityFile = "~/.ssh/id_ed25519_sk_ykc";
        };
        github = {
          hostname = "github.com";
          user = "git";
        };
      };
    };
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".ssh/allowed_signers".text = ''
      hi@ieuan.net sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEo+YmeZF08PM0Ojvt6hIUgkaxzHrdc7GUZS+UpEuoxvAAAABHNzaDo=
      hi@ieuan.net sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDlEPzSf59qfPwZRF5r5RzZ33DJR69U9xMyvu3yJrEcFAAAABHNzaDo=
      hi@ieuan.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICd3qvLJCEGwvZLWl5dUXI/WAV9a7DDTYa+NlDA9Yjeo
    '';
    ".ssh/sockets/.keep".text = "";
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
