# Smartcards (YubiKey / PIV) and the SSH/GnuPG agents that use them.
# Desktop-only companion to security.nix.
{
  # Smartcard daemon (YubiKey / PIV).
  services.pcscd.enable = true;

  programs.ssh = {
    startAgent = true;
    enableAskPassword = true;
  };

  programs.gnupg.agent.enable = true;

  environment.variables = {
    SSH_ASKPASS_REQUIRE = "prefer";
  };
}
