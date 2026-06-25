# Privilege escalation, mandatory access control, smartcards and agents.
{
  security.sudo.wheelNeedsPassword = true;
  # Only members of wheel may run the sudo binaries at all.
  security.sudo.execWheelOnly = true;

  # Mandatory access control: load AppArmor profiles and stop unconfined
  # processes that should have been confined.
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };

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
