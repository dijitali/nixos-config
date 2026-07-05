# Privilege escalation and mandatory access control, applicable to every
# host. Smartcard/agent tooling for the desktop machines lives in
# smartcard.nix.
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
}
