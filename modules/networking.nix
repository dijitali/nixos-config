# Networking, firewall and mesh/discovery services.
{
  networking = {
    networkmanager.enable = true;
    firewall.enable = true;
    nftables.enable = true;
  };

  services = {
    tailscale.enable = true;

    # Printer/service discovery on the local network.
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
