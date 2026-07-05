# Hardened OpenSSH daemon for hosts that accept inbound SSH (servers).
# Key-based auth only; user keys are declared in users/<user>/server.nix.
{
  services.openssh = {
    enable = true;
    # openFirewall defaults to true, so port 22 is admitted automatically.
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
