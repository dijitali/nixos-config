# NixOS VM test of jenkosrv-fsn1-3: boots the real host config (with the
# Hetzner-, tailnet- and ACME-specific parts swapped out below) next to a
# client machine, and checks every site answers as it does in production, over
# the firewall, and that state on /persist survives a reboot of the tmpfs root.
#
#   nix build .#checks.x86_64-linux.jenkosrv-fsn1-3 -L   # or `make test-server`
#
# For poking around: build `.driverInteractive` and run
# ./result/bin/nixos-test-driver, then `start_all()` / `server.shell_interact()`.
{ inputs, pkgs }:

pkgs.testers.runNixOSTest {
  name = "jenkosrv-fsn1-3";

  node.specialArgs = {
    inherit inputs;
    hostname = "jenkosrv-fsn1-3";
    user = "ieuan";
    headless = true;
  };

  nodes.server =
    { lib, ... }:
    {
      imports = [
        ../hosts/jenkosrv-fsn1-3
        ../users/ieuan/server.nix
      ];

      # Like production, / is a tmpfs and runtime state lives on a separate
      # disk at /persist (the Hetzner volume; matched there by vendor/model,
      # here by serial).
      virtualisation = {
        diskImage = null;
        memorySize = 2048;
        emptyDiskImages = [
          {
            size = 512;
            driveConfig.deviceExtraOpts.serial = "persist";
          }
        ];
        fileSystems."/persist" = {
          device = "/dev/disk/by-id/virtio-persist";
          fsType = "ext4";
          autoFormat = true;
          neededForBoot = true;
        };
      };

      # No Hetzner metadata service, tailnet key or public DNS for ACME here.
      server.hetznerMetadataIPv6 = lib.mkForce false;
      services.tailscale.enable = lib.mkForce false;
      web.localCerts = true;
      system.autoUpgrade.enable = lib.mkForce false;
      # The test framework configures the network on eth1; production's
      # catch-all DHCP network would claim it first.
      systemd.network.networks."10-wan".enable = false;
      # QEMU boots the kernel directly; GRUB would target the real disk.
      boot.loader.grub.enable = lib.mkForce false;
    };

  nodes.client =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.netcat ];
    };

  testScript =
    { nodes, ... }:
    let
      ip = nodes.server.networking.primaryIPAddress;
    in
    ''
      import json

      def get(url, args=""):
          """Status, redirect target and headers for url, resolved to the server."""
          host = url.split("/")[2]
          port = 443 if url.startswith("https") else 80
          out = client.succeed(
              f"curl -sk -o /dev/null -D - -w '%{{json}}' --resolve {host}:{port}:${ip} {args} '{url}'"
          )
          headers, _, meta = out.rpartition("\r\n\r\n")
          meta = json.loads(meta)
          return meta["http_code"], meta["redirect_url"] or "", headers.lower()

      def expect(url, code, location=""):
          got, loc, _ = get(url)
          assert (got, loc) == (code, location), f"{url}: got {got} {loc!r}, want {code} {location!r}"

      start_all()

      with subtest("server boots cleanly"):
          server.wait_for_unit("multi-user.target")
          server.succeed("findmnt -n /persist")
          server.succeed("findmnt -n /var/lib/caddy")
          failed = server.succeed("systemctl list-units --failed --plain --no-legend").strip()
          assert failed == "", f"failed units:\n{failed}"

      server.wait_for_unit("caddy.service")
      server.wait_for_open_port(443)
      # Stand-in for ieuan-net's pushed content.
      server.succeed("echo hello > /var/www/public/index.html")
      client.wait_for_unit("multi-user.target")

      with subtest("firewall: only SSH, HTTP and HTTPS reachable"):
          for port in (22, 80, 443):
              client.succeed(f"nc -z -w 5 ${ip} {port}")
          client.fail("nc -z -w 5 ${ip} 2019")

      with subtest("redirects"):
          expect("http://www.ieuan.net/", 308, "https://www.ieuan.net/")
          expect("https://ieuan.net/some/path", 301, "https://www.ieuan.net/some/path")
          expect("https://ieuan.co.uk/", 302, "https://www.ieuan.net/")
          expect("https://www.ieuan.co.uk/", 302, "https://www.ieuan.net/")
          expect("https://jensys.uk/", 301, "https://www.jensys.uk/")
          expect("https://openpgpkey.ieuan.net/", 301, "https://www.ieuan.net/")
          expect("https://www.ieuan.net/cv", 301, "https://www.ieuan.net/docs/cv/ieuan_jenkins_cv.pdf")

      with subtest("sites serve content"):
          code, _, headers = get("https://www.ieuan.net/")
          assert code == 200, code
          assert "strict-transport-security:" in headers, headers
          expect("https://beta.ieuan.net/", 200)
          expect("https://www.jensys.uk/", 200)
          expect("https://net.ieuan.net/", 200)
          expect("http://net.ieuan.net/", 200)

      with subtest("ip.ieuan.net echoes the client address"):
          body = client.succeed("curl -sk --resolve ip.ieuan.net:443:${ip} https://ip.ieuan.net/")
          assert body.strip() == "${nodes.client.networking.primaryIPAddress}", body

      with subtest("Home Assistant proxies require a client certificate"):
          for host in ("arg.ha.jnkns.uk", "wyk.ha.jnkns.uk"):
              client.fail(f"curl -sk --fail --resolve {host}:443:${ip} https://{host}/")

      with subtest("state on /persist survives a reboot"):
          machine_id = server.succeed("cat /etc/machine-id")
          certs = server.succeed("find /var/lib/caddy -name '*.crt' | sort")
          assert "www.ieuan.net" in certs, certs
          server.shutdown()
          server.start()
          server.wait_for_unit("caddy.service")
          assert server.succeed("cat /etc/machine-id") == machine_id
          assert server.succeed("find /var/lib/caddy -name '*.crt' | sort") == certs
          server.succeed("test -f /var/www/public/index.html")
          server.wait_for_open_port(443)
          expect("https://www.ieuan.net/", 200)
    '';
}
