# NixOS VM test of jenkosrv-fsn1-3: boots the real host config (with the
# Hetzner-, tailnet- and ACME-specific parts swapped out below) next to a
# client machine. This file only checks the server itself: a clean boot, the
# firewall, that Caddy serves every site host with a certificate, and that
# state on /persist survives a reboot of the tmpfs root.
#
# How each site behaves is tested by its own repo: a site flake may export
# `caddyTest`, Python run here as one subtest per site (see the helpers in
# testScript for what it can use).
#
#   nix build .#checks.x86_64-linux.jenkosrv-fsn1-3 -L   # or `make test-server`
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
      sites = nodes.server.web.sites;
      siteTests = pkgs.writeText "site-tests.json" (
        builtins.toJSON (
          builtins.mapAttrs (_: site: site.caddyTest) (pkgs.lib.filterAttrs (_: site: site ? caddyTest) sites)
        )
      );
    in
    ''
      import json

      server_ip = "${nodes.server.networking.primaryIPAddress}"
      client_ip = "${nodes.client.networking.primaryIPAddress}"

      def walk(node):
          """Every dict anywhere inside a JSON value."""
          if isinstance(node, dict):
              yield node
              node = list(node.values())
          if isinstance(node, list):
              for item in node:
                  yield from walk(item)

      # Helpers for the sites' caddyTest snippets, which also get `server`,
      # `client`, `server_ip`, `client_ip` and `subtest`. Requests go from the
      # client to the server by name (curl --resolve); certificates come from
      # Caddy's internal CA, so they are not verified.
      def get(url, *curl_args):
          """(status, redirect target or "", lower-cased headers) for url."""
          host = url.split("/")[2]
          port = 443 if url.startswith("https:") else 80
          args = " ".join(curl_args)
          out = client.succeed(
              f"curl -sk -o /dev/null -D - -w '%{{json}}' --resolve {host}:{port}:{server_ip} {args} '{url}'"
          )
          head, _, meta = out.rpartition("\r\n\r\n")
          meta = json.loads(meta)
          headers = {}
          for line in head.splitlines()[1:]:
              name, _, value = line.partition(":")
              headers[name.strip().lower()] = value.strip()
          return meta["http_code"], meta["redirect_url"] or "", headers

      def expect(url, code, location=""):
          """Assert url answers with this status (and redirect target)."""
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
      client.wait_for_unit("multi-user.target")

      with subtest("firewall: only SSH, HTTP and HTTPS reachable"):
          for port in (22, 80, 443):
              client.succeed(f"nc -z -w 5 {server_ip} {port}")
          client.fail(f"nc -z -w 5 {server_ip} 2019")

      # Site hosts, from the config Caddy is running (its admin API, localhost
      # only), so this file needs no list of them.
      config = json.loads(server.succeed("curl -sf localhost:2019/config/"))
      https_hosts = set()
      for srv in config["apps"]["http"]["servers"].values():
          if ":443" in srv.get("listen", []):
              https_hosts.update(h for d in walk(srv.get("routes", [])) for h in d.get("host", []))
      assert len(https_hosts) >= ${toString (builtins.length (builtins.attrNames sites))}, https_hosts

      with subtest("every site host has a certificate and answers over HTTP"):
          server.wait_until_succeeds(
              "for h in " + " ".join(sorted(https_hosts))
              + "; do test -n \"$(find /var/lib/caddy -name \"$h.crt\")\" || exit 1; done",
              timeout=60,
          )
          for host in sorted(https_hosts):
              code, _, _ = get(f"http://{host}/")
              assert code < 500, f"http://{host}/: {code}"

      site_tests = json.load(open("${siteTests}"))
      for name, snippet in sorted(site_tests.items()):
          with subtest(f"site: {name}"):
              exec(snippet, dict(globals()))

      with subtest("state on /persist survives a reboot"):
          machine_id = server.succeed("cat /etc/machine-id")
          certs = server.succeed("find /var/lib/caddy -name '*.crt' | sort")
          server.shutdown()
          server.start()
          server.wait_for_unit("caddy.service")
          assert server.succeed("cat /etc/machine-id") == machine_id
          assert server.succeed("find /var/lib/caddy -name '*.crt' | sort") == certs
    '';
}
