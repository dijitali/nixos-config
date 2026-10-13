# Headless counterpart to ./nixos.nix: the same account, but no desktop groups,
# no Home Manager and SSH-key-only access. Used by mkSystem when
# `headless = true`.
{ pkgs, ... }:

{
  # Accounts come only from this config. On the impermanent servers /etc/shadow
  # is rebuilt every boot anyway, so a `passwd` change would be lost.
  users.mutableUsers = false;

  users.users.ieuan = {
    isNormalUser = true;
    description = "Ieuan";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICd3qvLJCEGwvZLWl5dUXI/WAV9a7DDTYa+NlDA9Yjeo hi@ieuan.net"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEo+YmeZF08PM0Ojvt6hIUgkaxzHrdc7GUZS+UpEuoxvAAAABHNzaDo= hi@ieuan.net (yka)"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDlEPzSf59qfPwZRF5r5RzZ33DJR69U9xMyvu3yJrEcFAAAABHNzaDo= hi@ieuan.net (ykC)"
    ];
  };

  # zsh is the login shell above; enabling it system-wide installs the shell
  # init so a login over SSH gets a working environment. There's no Home
  # Manager here, so the interactive setup from ./home.nix is repeated in
  # /etc/zshrc instead.
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 100000;
    # In a directory of its own so an impermanent host can persist it: zsh
    # rewrites the history by renaming a new file over it, which fails on a
    # bind-mounted file.
    histFile = "$HOME/.local/state/zsh/history";
    setOptions = [
      "EXTENDED_HISTORY"
      "HIST_EXPIRE_DUPS_FIRST"
      "HIST_FCNTL_LOCK"
      "HIST_IGNORE_ALL_DUPS"
      "HIST_IGNORE_SPACE"
      "SHARE_HISTORY"
    ];
  };
  programs.fzf = {
    keybindings = true;
    fuzzyCompletion = true;
  };

  # zsh runs its new-user wizard when ~ has no startup files. The settings
  # above all live in /etc, so an empty ~/.zshrc is enough to skip it; `f`
  # only creates it if missing, which on an impermanent root is every boot.
  systemd.tmpfiles.rules = [
    "f /home/ieuan/.zshrc 0644 ieuan users - # Configured system-wide in /etc/zshrc (nixos-config: users/ieuan/server.nix)."
  ];
}
