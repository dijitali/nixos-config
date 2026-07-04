# Networking, firewall and mesh/discovery services.
{
  networking = {
    networkmanager = {
      enable = true;
      wifi = {
        scanRandMacAddress = true; # random MAC while scanning
        macAddress = "stable-ssid"; # stable per-network, random across networks
      };
      # Ignore the DNS servers handed out by DHCP so our global resolver
      # (Quad9, configured on systemd-resolved below) is authoritative on
      # ordinary networks instead of the ISP/router resolver. A VPN that
      # installs its own DNS with a `~.` routing domain (Mozilla/Mullvad)
      # still overrides this while connected.
      settings.connection = {
        "ipv4.ignore-auto-dns" = true;
        "ipv6.ignore-auto-dns" = true;
      };
    };
    firewall.enable = true;
    nftables.enable = true;
  };

  services = {
    tailscale.enable = true;

    # systemd-resolved as the local stub resolver. The `#hostname` suffix on
    # each server names its TLS certificate so DNSOverTLS can verify it.
    # Opportunistic DNSOverTLS upgrades to encrypted DNS when the server
    # supports it and falls back to plain DNS when it doesn't (so captive
    # portals still work). A connected VPN pushes its own DNS with a `~.`
    # routing domain and transparently overrides this global config; when the
    # VPN drops, resolved falls back here.
    resolved = {
      enable = true;
      settings.Resolve = {
        # Primary Quad9 (malware-blocking, DNSSEC-validating anycast), then
        # Mullvad. resolved uses the first reachable server and rotates to the
        # next on repeated failure, so Quad9 is used normally and Mullvad takes
        # over if Quad9 is unreachable.
        DNS = "9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net 194.242.2.2#dns.mullvad.net 2a07:e340::2#dns.mullvad.net";
        DNSOverTLS = "opportunistic";
      };
    };

    # Printer/service discovery on the local network.
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
