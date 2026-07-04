# Networking, firewall and mesh/discovery services.
{
  networking = {
    networkmanager = {
      enable = true;
      wifi = {
        scanRandMacAddress = true; # random MAC while scanning
        macAddress = "stable-ssid"; # stable per-network, random across networks
      };
    };
    firewall.enable = true;
    nftables.enable = true;
  };

  services = {
    tailscale.enable = true;

    # systemd-resolved as the local stub resolver. NetworkManager hands it the
    # per-network DNS servers; opportunistic DNSOverTLS upgrades to encrypted
    # DNS when the server supports it and falls back to plain DNS when it
    # doesn't (so captive portals still work).
    resolved = {
      enable = true;
      settings.Resolve.DNSOverTLS = "opportunistic";
    };

    # Printer/service discovery on the local network.
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
